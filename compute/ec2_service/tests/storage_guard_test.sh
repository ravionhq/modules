#!/usr/bin/env bash
# Runtime check for the data volume discovery/mount scripts and the deploy
# storage guard this module generates.
#
# The tofu tests assert what gets rendered into user data and the deploy
# document; this script runs the rendered shell against stubbed disk tools
# (lsblk, blkid, findmnt, mountpoint, mount, mkfs) to confirm the scripts
# format only brand-new disks, remount an existing data volume after a root
# volume replacement, never guess between several candidate disks, and
# that the guard stops a deploy before the running app is touched.
#
# Usage: tests/storage_guard_test.sh
# Requires: tofu (to render the templates) and python3.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PASSED=0

fail() {
  echo "FAIL: $*" >&2
  if [ -f "$WORK_DIR/out" ]; then
    echo "--- output ---" >&2
    cat "$WORK_DIR/out" >&2
  fi
  exit 1
}

pass() {
  PASSED=$((PASSED + 1))
  echo "ok - $*"
}

# Render a template with templatefile() exactly as the module does.
render() {
  local template="$1" vars="$2" out="$3"
  mkdir -p "$WORK_DIR/render"
  (
    cd "$WORK_DIR/render"
    echo "jsonencode(templatefile(\"$MODULE_DIR/templates/$template\", $vars))" | tofu console
  ) | python3 -c 'import json, sys; sys.stdout.write(json.loads(json.loads(sys.stdin.read())))' >"$out"
}

MOUNT_VARS='{ data_volume_device_links = "/dev/xvdf /dev/sdf", data_volume_label = "ravion-data", data_volume_mount_path = "/data" }'
render data_volume_mount.sh.tpl "$MOUNT_VARS" "$WORK_DIR/mount.sh"
render data_volume_format.sh.tpl '{}' "$WORK_DIR/format.sh"

render_guard() {
  local data_enabled="$1" efs_enabled="$2" out="$3"
  python3 - "$WORK_DIR/mount.sh" "$WORK_DIR/guard_vars.json" "$data_enabled" "$efs_enabled" <<'PY'
import json, sys
mount_script = open(sys.argv[1]).read()
json.dump({
    "data_volume_enabled": sys.argv[3] == "true",
    "efs_enabled": sys.argv[4] == "true",
    "data_volume_mount_path": "/data",
    "efs_mount_path": "/mnt/efs",
    "data_volume_mount_script": mount_script,
}, open(sys.argv[2], "w"))
PY
  render ensure_storage.sh.tpl "jsondecode(file(\"$WORK_DIR/guard_vars.json\"))" "$out"
}

render_guard true false "$WORK_DIR/guard_data.sh"
render_guard false true "$WORK_DIR/guard_efs.sh"
render_guard false false "$WORK_DIR/guard_none.sh"

# The boot sequence user data runs for the data volume.
{
  echo 'set -euo pipefail'
  cat "$WORK_DIR/mount.sh" "$WORK_DIR/format.sh"
  echo 'ravion_format_new_data_volume || echo "Data volume: formatting failed" >&2'
  echo 'ravion_mount_data_volume || true'
} >"$WORK_DIR/boot.sh"

# A deploy prelude: the guard, then the point where the running app is stopped.
make_deploy() {
  {
    echo 'set -euo pipefail'
    cat "$1"
    echo 'echo "STOPPING RUNNING APP"'
  } >"$2"
}
make_deploy "$WORK_DIR/guard_data.sh" "$WORK_DIR/deploy_data.sh"
make_deploy "$WORK_DIR/guard_efs.sh" "$WORK_DIR/deploy_efs.sh"
make_deploy "$WORK_DIR/guard_none.sh" "$WORK_DIR/deploy_none.sh"

################################################################################
# Stubbed disk tools. State lives under $STATE:
#   disks             whole disks, one per line (the root disk is /dev/nvme0n1)
#   fs/<disk>         filesystem type    label/<disk>  filesystem label
#   uuid/<disk>       filesystem UUID    links/<name>  device a link resolves to
#   mounts            "<device> <path> [fstype]" for every mounted filesystem
#   calls             every mkfs / mount call
################################################################################

STUBS="$WORK_DIR/stubs"
mkdir -p "$STUBS"

stub() {
  cat >"$STUBS/$1"
  chmod 755 "$STUBS/$1"
}

stub findmnt <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-nvo" ]; then
  # findmnt -nvo SOURCE|FSTYPE <mount path>
  line=$(awk -v p="$3" '$2 == p { print; exit }' "$STATE/mounts")
  [ -n "$line" ] || exit 1
  case "$2" in
    SOURCE) echo "$line" | awk '{ print $1 }' ;;
    FSTYPE) echo "$line" | awk '{ print $3 }' ;;
    *) echo "unexpected findmnt $*" >&2; exit 64 ;;
  esac
  exit 0
fi
target=0
[ "$1" = "-rno" ] && target=1
dev="${@: -1}"
line=$(awk -v d="$dev" '$1 == d { print; exit }' "$STATE/mounts")
[ -n "$line" ] || exit 1
if [ "$target" = 1 ]; then echo "${line#* }"; fi
exit 0
EOF

stub lsblk <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "-npo PKNAME /dev/nvme0n1p1") echo /dev/nvme0n1 ;;
  "-npo PKNAME /dev/"*) ;;
  "-npo PKNAME "*) exit 1 ;;
  "-dnpo NAME -e 7,11") cat "$STATE/disks" ;;
  "-npo FSTYPE,PTTYPE "*)
    dev="${@: -1}"
    if [ "$dev" = /dev/nvme0n1 ]; then echo " gpt"; echo "xfs "; exit 0; fi
    cat "$STATE/fs/${dev##*/}" 2>/dev/null || echo " "
    ;;
  *) echo "unexpected lsblk $*" >&2; exit 64 ;;
esac
EOF

stub blkid <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-c" ]; then
  label="${4#LABEL=}"
  found=1
  for f in "$STATE"/label/*; do
    [ -e "$f" ] || continue
    if [ "$(cat "$f")" = "$label" ]; then echo "/dev/${f##*/}"; found=0; fi
  done
  exit "$((found * 2))"
fi
dev="${@: -1}"
name="${dev##*/}"
case "$*" in
  "-p -s TYPE -o value "*) cat "$STATE/fs/$name" 2>/dev/null || exit 2 ;;
  "-p -s UUID -o value "*) cat "$STATE/uuid/$name" 2>/dev/null || exit 2 ;;
  "-p "*) [ -f "$STATE/fs/$name" ] || exit 2 ;;
  *) echo "unexpected blkid $*" >&2; exit 64 ;;
esac
EOF

stub mountpoint <<'EOF'
#!/usr/bin/env bash
awk -v p="$2" '$2 == p { found = 1 } END { exit !found }' "$STATE/mounts"
EOF

stub mount <<'EOF'
#!/usr/bin/env bash
echo "mount $*" >>"$STATE/calls"
if [ "$*" = "-a -t efs" ]; then
  if [ -f "$STATE/efs_reachable" ]; then echo "127.0.0.1:/ /mnt/efs nfs4" >>"$STATE/mounts"; exit 0; fi
  exit 32
fi
[ -f "$STATE/fs/${3##*/}" ] || exit 32
echo "$3 $4 $2" >>"$STATE/mounts"
EOF

stub mkfs <<'EOF'
#!/usr/bin/env bash
echo "mkfs $*" >>"$STATE/calls"
dev="${@: -1}"
name="${dev##*/}"
[ ! -f "$STATE/fs/$name" ] || { echo "mkfs on a disk with a filesystem" >&2; exit 99; }
echo "$2" >"$STATE/fs/$name"
echo "$4" >"$STATE/label/$name"
echo "uuid-$name-new" >"$STATE/uuid/$name"
EOF

stub readlink <<'EOF'
#!/usr/bin/env bash
cat "$STATE/links/${2##*/}"
EOF

stub mkdir <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

stub cloud-init <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

stub timeout <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF

# Fresh state: a root disk plus the given extra disks, nothing mounted
# except the root filesystem.
new_state() {
  STATE="$WORK_DIR/state-$1"
  shift
  rm -rf "$STATE"
  mkdir -p "$STATE/fs" "$STATE/label" "$STATE/uuid" "$STATE/links" "$STATE/devlinks"
  echo /dev/nvme0n1 >"$STATE/disks"
  for disk in "$@"; do echo "$disk" >>"$STATE/disks"; done
  echo "/dev/nvme0n1p1 /" >"$STATE/mounts"
  : >"$STATE/calls"
  : >"$STATE/fstab"
  export STATE
}

add_fs() { # disk fstype [label]
  echo "$2" >"$STATE/fs/${1##*/}"
  echo "uuid-${1##*/}" >"$STATE/uuid/${1##*/}"
  if [ -n "${3:-}" ]; then echo "$3" >"$STATE/label/${1##*/}"; fi
}

link_data_device() { # disk the /dev/xvdf link resolves to
  : >"$STATE/devlinks/xvdf"
  echo "$1" >"$STATE/links/xvdf"
}

run_script() {
  PATH="$STUBS:$PATH" \
    RAVION_FSTAB="$STATE/fstab" \
    RAVION_DATA_DEVICE_LINKS="$STATE/devlinks/xvdf $STATE/devlinks/sdf" \
    bash "$1" >"$WORK_DIR/out" 2>&1
}

mounted_at() { awk -v p="$1" '$2 == p { print $1 }' "$STATE/mounts"; }

################################################################################
# Boot (user data)
################################################################################

new_state fresh_linked /dev/nvme1n1
link_data_device /dev/nvme1n1
run_script "$WORK_DIR/boot.sh" || fail "boot on a new instance failed"
grep -qx "mkfs -t xfs -L ravion-data /dev/nvme1n1" "$STATE/calls" || fail "a new data volume must be formatted with the ravion-data label"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "a new data volume must be mounted at /data"
grep -qx "UUID=uuid-nvme1n1-new /data xfs defaults,nofail 0 2" "$STATE/fstab" || fail "the data volume must be added to fstab by UUID with nofail"
run_script "$WORK_DIR/boot.sh" || fail "a second boot run failed"
[ "$(grep -c '^mkfs' "$STATE/calls")" = 1 ] || fail "a second run must not format again"
[ "$(grep -c ' /data ' "$STATE/fstab")" = 1 ] || fail "a second run must not duplicate the fstab entry"
pass "new instance: blank linked disk is labelled, formatted once, mounted, and recorded in fstab"

new_state rebuilt_root_labelled /dev/nvme1n1
link_data_device /dev/nvme1n1
add_fs /dev/nvme1n1 xfs ravion-data
run_script "$WORK_DIR/boot.sh" || fail "boot after a root replacement failed"
! grep -q '^mkfs' "$STATE/calls" || fail "an existing data volume must never be formatted"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "the labelled data volume must be remounted after a root replacement"
grep -qx "UUID=uuid-nvme1n1 /data xfs defaults,nofail 0 2" "$STATE/fstab" || fail "the remounted volume must be added back to the fresh fstab"
pass "rebuilt root: labelled data volume is remounted and re-added to fstab without formatting"

new_state rebuilt_root_old_volume /dev/nvme1n1
add_fs /dev/nvme1n1 xfs
run_script "$WORK_DIR/boot.sh" || fail "boot with an unlabelled volume failed"
! grep -q '^mkfs' "$STATE/calls" || fail "an unlabelled volume with a filesystem must never be formatted"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "the only unmounted disk with a filesystem must be mounted"
pass "rebuilt root, volume from an older release (no label, no device link): the single candidate is mounted"

new_state linked_existing_unlabelled /dev/nvme1n1 /dev/nvme2n1
link_data_device /dev/nvme2n1
add_fs /dev/nvme1n1 xfs
add_fs /dev/nvme2n1 ext4
run_script "$WORK_DIR/boot.sh" || fail "boot with a linked volume failed"
! grep -q '^mkfs' "$STATE/calls" || fail "a linked volume with a filesystem must never be formatted"
[ "$(mounted_at /data)" = /dev/nvme2n1 ] || fail "the linked data volume must win over other disks"
grep -q " /data ext4 defaults,nofail" "$STATE/fstab" || fail "the fstab entry must use the volume's own filesystem type"
pass "device link identifies the data volume among several disks with filesystems"

new_state two_blank /dev/nvme1n1 /dev/nvme2n1
run_script "$WORK_DIR/boot.sh" || fail "boot with two blank disks must not fail the bootstrap"
! grep -q '^mkfs' "$STATE/calls" || fail "with two blank disks and no device link nothing may be formatted"
grep -q "several blank disks found" "$WORK_DIR/out" || fail "skipping the format must be logged"
[ -z "$(mounted_at /data)" ] || fail "nothing may be mounted when the data volume is ambiguous"
pass "two blank disks without a device link (e.g. instance store): nothing is formatted or mounted"

new_state existing_and_blank /dev/nvme1n1 /dev/nvme2n1
add_fs /dev/nvme1n1 xfs
run_script "$WORK_DIR/boot.sh" || fail "boot with an existing volume and a blank disk failed"
! grep -q '^mkfs' "$STATE/calls" || fail "a blank disk must not be formatted while another disk already has a filesystem"
[ -z "$(cat "$STATE/label/nvme2n1" 2>/dev/null)" ] || fail "the blank disk must not get the data label"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "the existing volume must be mounted, not the blank disk"
grep -q "already has a filesystem; not formatting another disk" "$WORK_DIR/out" || fail "skipping the format must be logged"
pass "existing unlabelled volume plus a blank disk, no device link: nothing is formatted and the existing volume is mounted"

new_state two_candidates /dev/nvme1n1 /dev/nvme2n1
add_fs /dev/nvme1n1 xfs
add_fs /dev/nvme2n1 xfs
run_script "$WORK_DIR/boot.sh" || fail "boot with two candidates must not fail the bootstrap"
[ -z "$(mounted_at /data)" ] || fail "with two unlabelled candidates nothing may be mounted"
grep -q "not guessing which one is the data volume" "$WORK_DIR/out" || fail "the ambiguity must be logged"
pass "two unmounted disks with filesystems and no label or link: nothing is mounted"

new_state two_labelled /dev/nvme1n1 /dev/nvme2n1
add_fs /dev/nvme1n1 xfs ravion-data
add_fs /dev/nvme2n1 xfs ravion-data
run_script "$WORK_DIR/boot.sh" || fail "boot with two labelled disks must not fail the bootstrap"
[ -z "$(mounted_at /data)" ] || fail "with two labelled disks nothing may be mounted"
grep -q "several unmounted disks are labelled ravion-data" "$WORK_DIR/out" || fail "the label ambiguity must be logged"
pass "two disks labelled ravion-data (e.g. a restored snapshot attached): nothing is mounted"

new_state fstab_present /dev/nvme1n1
add_fs /dev/nvme1n1 xfs ravion-data
echo "UUID=uuid-nvme1n1 /data xfs defaults,nofail 0 2" >"$STATE/fstab"
run_script "$WORK_DIR/boot.sh" || fail "boot with an existing fstab entry failed"
[ "$(grep -c ' /data ' "$STATE/fstab")" = 1 ] || fail "an existing fstab entry for the path must not be duplicated"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "the volume must still be mounted when fstab already lists it"
pass "existing fstab entry (restored by Ravion) is kept and not duplicated"

################################################################################
# Deploy storage guard
################################################################################

new_state guard_unmounted /dev/nvme1n1
add_fs /dev/nvme1n1 xfs ravion-data
run_script "$WORK_DIR/deploy_data.sh" || fail "the guard must mount a present data volume and let the deploy continue"
[ "$(mounted_at /data)" = /dev/nvme1n1 ] || fail "the guard must mount the data volume"
grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the deploy must continue once the volume is mounted"
pass "guard: mounts an unmounted data volume, then lets the deploy continue"

new_state guard_already_mounted /dev/nvme1n1
add_fs /dev/nvme1n1 xfs
echo "/dev/nvme1n1 /data" >>"$STATE/mounts"
run_script "$WORK_DIR/deploy_data.sh" || fail "the guard must pass when the volume is mounted"
! grep -q '^mount' "$STATE/calls" || fail "the guard must not remount a mounted volume"
pass "guard: already-mounted data volume passes untouched"

for scenario in missing ambiguous blank; do
  case "$scenario" in
    missing) new_state "guard_$scenario" ;;
    ambiguous)
      new_state "guard_$scenario" /dev/nvme1n1 /dev/nvme2n1
      add_fs /dev/nvme1n1 xfs
      add_fs /dev/nvme2n1 xfs
      ;;
    blank)
      new_state "guard_$scenario" /dev/nvme1n1
      link_data_device /dev/nvme1n1
      ;;
  esac
  if run_script "$WORK_DIR/deploy_data.sh"; then
    fail "the guard must fail the deploy when the data volume is $scenario"
  fi
  grep -q "Data volume not mounted at /data; refusing to start the app so it does not write to the root disk." "$WORK_DIR/out" || fail "the guard must explain why ($scenario)"
  ! grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the running app must not be stopped ($scenario)"
  ! grep -q '^mkfs' "$STATE/calls" || fail "the guard must never format a disk ($scenario)"
  pass "guard: fails closed before stopping the app when the data volume is $scenario"
done

new_state guard_root_bind /dev/nvme1n1
add_fs /dev/nvme1n1 xfs ravion-data
echo "/dev/nvme0n1p1 /data xfs" >>"$STATE/mounts"
if run_script "$WORK_DIR/deploy_data.sh"; then
  fail "the guard must fail when the data path is mounted from the root disk"
fi
grep -q "/data is on the root disk (/dev/nvme0n1p1), not the data volume" "$WORK_DIR/out" || fail "the root-disk failure must be explained"
! grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the running app must not be stopped when /data is on the root disk"
pass "guard: fails closed when the data path is a mount from the root disk"

new_state guard_data_on_nfs
echo "127.0.0.1:/ /data nfs4" >>"$STATE/mounts"
if run_script "$WORK_DIR/deploy_data.sh"; then
  fail "the guard must fail when the data path holds a network mount"
fi
grep -q "/data is mounted from 127.0.0.1:/, not a local data volume" "$WORK_DIR/out" || fail "the network-mount failure must be explained"
! grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the running app must not be stopped when /data is a network mount"
pass "guard: fails closed when the data path holds EFS or another network mount"

new_state guard_efs_wrong_fs /dev/nvme1n1
add_fs /dev/nvme1n1 xfs
echo "/dev/nvme1n1 /mnt/efs xfs" >>"$STATE/mounts"
if run_script "$WORK_DIR/deploy_efs.sh"; then
  fail "the guard must fail when the EFS path holds a local disk"
fi
grep -q "/mnt/efs holds a xfs filesystem, not EFS" "$WORK_DIR/out" || fail "the wrong-filesystem failure must be explained"
! grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the running app must not be stopped when EFS is the wrong filesystem"
pass "guard: fails closed when the EFS path holds a local disk instead of EFS"

new_state guard_efs_down
if run_script "$WORK_DIR/deploy_efs.sh"; then
  fail "the guard must fail the deploy when EFS cannot be mounted"
fi
grep -q "EFS file system not mounted at /mnt/efs; refusing to start the app" "$WORK_DIR/out" || fail "the EFS failure must be explained"
! grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the running app must not be stopped when EFS is missing"
pass "guard: fails closed when EFS cannot be mounted"

new_state guard_efs_up
: >"$STATE/efs_reachable"
run_script "$WORK_DIR/deploy_efs.sh" || fail "the guard must pass once mount -a mounts EFS"
grep -qx "mount -a -t efs" "$STATE/calls" || fail "the guard must try mount -a -t efs"
grep -q "STOPPING RUNNING APP" "$WORK_DIR/out" || fail "the deploy must continue once EFS is mounted"
pass "guard: mounts EFS from fstab, then lets the deploy continue"

[ -z "$(tr -d '[:space:]' <"$WORK_DIR/guard_none.sh")" ] || fail "without a data volume or EFS the guard must render empty"
new_state guard_none
run_script "$WORK_DIR/deploy_none.sh" || fail "a deploy without extra storage must not be guarded"
pass "guard: renders empty without a data volume or EFS"

echo "PASS: $PASSED storage checks"
