# Data volume discovery and mount, shared by instance boot (user data) and
# the deploy storage guard. Defines shell functions only.
#
# The data volume is found, in order: by its filesystem label, by the EBS
# device name the launch template attaches it as, or as the only other
# unmounted disk that already has a filesystem. When several disks could be
# the data volume, nothing is guessed: the problem is logged and the volume
# stays unmounted. Nothing here formats a disk; formatting a brand-new volume
# lives in data_volume_format.sh.tpl, which only instance boot includes.
RAVION_DATA_MOUNT_PATH="${data_volume_mount_path}"
RAVION_DATA_LABEL="${data_volume_label}"
RAVION_DATA_DEVICE_LINKS="$${RAVION_DATA_DEVICE_LINKS:-${data_volume_device_links}}"
RAVION_FSTAB="$${RAVION_FSTAB:-/etc/fstab}"
RAVION_DATA_DEVICE=""
RAVION_DATA_PROBLEM=""

# Whole disk that holds the root filesystem.
ravion_root_disk() {
  local source parent
  source=$(findmnt -nvo SOURCE / 2>/dev/null || true)
  parent=$(lsblk -npo PKNAME "$source" 2>/dev/null | head -n 1 || true)
  if [ -n "$parent" ]; then echo "$parent"; else echo "$source"; fi
}

# Whole disks other than the root disk; loop devices and CD-ROMs excluded.
ravion_other_disks() {
  local root disk
  root=$(ravion_root_disk)
  for disk in $(lsblk -dnpo NAME -e 7,11 2>/dev/null || true); do
    if [ "$disk" != "$root" ]; then echo "$disk"; fi
  done
}

ravion_fs_type() {
  blkid -p -s TYPE -o value "$1" 2>/dev/null || true
}

ravion_has_data_fs() {
  local fs_type
  fs_type=$(ravion_fs_type "$1")
  [ -n "$fs_type" ] && [ "$fs_type" != "swap" ]
}

ravion_is_mounted() {
  findmnt -rn -S "$1" >/dev/null 2>&1
}

# Blank: no filesystem or partition table on the disk or any partition.
# blkid exits 2 only when it positively found no signature.
ravion_is_blank() {
  local status=0
  if [ -n "$(lsblk -npo FSTYPE,PTTYPE "$1" 2>/dev/null | tr -d '[:space:]')" ]; then
    return 1
  fi
  blkid -p "$1" >/dev/null 2>&1 || status=$?
  [ "$status" -eq 2 ]
}

# Disk the launch template attached as the data volume, when the AMI
# exposes EBS device-name links (Amazon Linux does).
ravion_linked_disk() {
  local link
  for link in $RAVION_DATA_DEVICE_LINKS; do
    if [ -e "$link" ]; then
      readlink -f "$link"
      return 0
    fi
  done
  return 0
}

ravion_labeled_disks() {
  blkid -c /dev/null -t LABEL="$RAVION_DATA_LABEL" -o device 2>/dev/null || true
}

# Sets RAVION_DATA_DEVICE to the unmounted data volume, or explains in
# RAVION_DATA_PROBLEM why none was picked.
ravion_find_data_volume() {
  local disk candidates="" count=0 mounted_at
  RAVION_DATA_DEVICE=""
  RAVION_DATA_PROBLEM=""

  for disk in $(ravion_labeled_disks); do
    if ! ravion_is_mounted "$disk"; then
      candidates="$candidates $disk"
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 1 ]; then
    RAVION_DATA_PROBLEM="several unmounted disks are labelled $RAVION_DATA_LABEL ($candidates ); not guessing which one to mount"
    return 0
  fi
  if [ "$count" -eq 1 ]; then
    RAVION_DATA_DEVICE="$${candidates# }"
    return 0
  fi

  disk=$(ravion_linked_disk)
  if [ -n "$disk" ]; then
    if ravion_is_mounted "$disk"; then
      mounted_at=$(findmnt -rno TARGET -S "$disk" 2>/dev/null | head -n 1 || true)
      RAVION_DATA_PROBLEM="data volume $disk is mounted at $mounted_at, not at $RAVION_DATA_MOUNT_PATH"
    elif ravion_has_data_fs "$disk"; then
      RAVION_DATA_DEVICE="$disk"
    else
      RAVION_DATA_PROBLEM="data volume $disk has no filesystem; only instance boot formats a new data volume"
    fi
    return 0
  fi

  for disk in $(ravion_other_disks); do
    if ravion_has_data_fs "$disk" && ! ravion_is_mounted "$disk"; then
      candidates="$candidates $disk"
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 1 ]; then
    RAVION_DATA_PROBLEM="several unmounted disks have a filesystem ($candidates ); not guessing which one is the data volume"
  elif [ "$count" -eq 1 ]; then
    RAVION_DATA_DEVICE="$${candidates# }"
  else
    RAVION_DATA_PROBLEM="no unmounted data volume was found. Instances launched before the data volume was enabled have none; replace them to get one"
  fi
  return 0
}

# Mounts the data volume at its path unless something is already mounted
# there, and records it in fstab by UUID when the path has no entry yet.
ravion_mount_data_volume() {
  local uuid fs_type
  if mountpoint -q "$RAVION_DATA_MOUNT_PATH"; then
    return 0
  fi
  ravion_find_data_volume
  if [ -z "$RAVION_DATA_DEVICE" ]; then
    echo "Data volume: $RAVION_DATA_PROBLEM" >&2
    return 0
  fi
  uuid=$(blkid -p -s UUID -o value "$RAVION_DATA_DEVICE" 2>/dev/null || true)
  fs_type=$(ravion_fs_type "$RAVION_DATA_DEVICE")
  mkdir -p "$RAVION_DATA_MOUNT_PATH"
  if [ -n "$uuid" ] && ! awk -v path="$RAVION_DATA_MOUNT_PATH" '$1 !~ /^#/ && $2 == path { found = 1 } END { exit !found }' "$RAVION_FSTAB" 2>/dev/null; then
    echo "Data volume: adding UUID=$uuid to $RAVION_FSTAB"
    echo "UUID=$uuid $RAVION_DATA_MOUNT_PATH $fs_type defaults,nofail 0 2" >>"$RAVION_FSTAB"
  fi
  echo "Data volume: mounting $RAVION_DATA_DEVICE at $RAVION_DATA_MOUNT_PATH"
  if ! mount -t "$fs_type" "$RAVION_DATA_DEVICE" "$RAVION_DATA_MOUNT_PATH"; then
    RAVION_DATA_PROBLEM="mounting $RAVION_DATA_DEVICE at $RAVION_DATA_MOUNT_PATH failed"
    echo "Data volume: $RAVION_DATA_PROBLEM" >&2
  fi
  return 0
}
