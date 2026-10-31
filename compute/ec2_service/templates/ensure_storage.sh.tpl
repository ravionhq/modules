%{ if data_volume_enabled || efs_enabled ~}
# Storage guard: the app only starts on top of its real storage. It runs
# before the running app is stopped, so a failure leaves that app alone.
if command -v cloud-init >/dev/null 2>&1; then
  # A just-launched or just-rebuilt instance can still be running its
  # bootstrap, which formats and mounts storage.
  timeout 600 cloud-init status --wait >/dev/null 2>&1 || true
fi
%{ endif ~}
%{ if data_volume_enabled ~}
${data_volume_mount_script}
ravion_mount_data_volume || true
if ! mountpoint -q "${data_volume_mount_path}"; then
  echo "Data volume not mounted at ${data_volume_mount_path}; refusing to start the app so it does not write to the root disk. $${RAVION_DATA_PROBLEM:-}" >&2
  exit 1
fi
# Something mounted there is not enough: it must be a local disk other than
# the root disk (not a bind mount of a root directory, not EFS).
RAVION_DATA_SOURCE=$(findmnt -nvo SOURCE "${data_volume_mount_path}" 2>/dev/null | head -n 1 || true)
RAVION_DATA_DISK=$(lsblk -npo PKNAME "$RAVION_DATA_SOURCE" 2>/dev/null | head -n 1 || true)
RAVION_DATA_DISK="$${RAVION_DATA_DISK:-$RAVION_DATA_SOURCE}"
case "$RAVION_DATA_DISK" in
  /dev/*) ;;
  *)
    echo "${data_volume_mount_path} is mounted from $${RAVION_DATA_SOURCE:-an unknown source}, not a local data volume; refusing to start the app." >&2
    exit 1
    ;;
esac
if [ "$RAVION_DATA_DISK" = "$(ravion_root_disk)" ]; then
  echo "${data_volume_mount_path} is on the root disk ($RAVION_DATA_SOURCE), not the data volume; refusing to start the app." >&2
  exit 1
fi
echo "Storage check: data volume $RAVION_DATA_SOURCE mounted at ${data_volume_mount_path}"
%{ endif ~}
%{ if efs_enabled ~}
if ! mountpoint -q "${efs_mount_path}"; then
  mkdir -p "${efs_mount_path}"
  mount -a -t efs || true
fi
if ! mountpoint -q "${efs_mount_path}"; then
  echo "EFS file system not mounted at ${efs_mount_path}; refusing to start the app so it does not write to the root disk." >&2
  exit 1
fi
# EFS mounts (amazon-efs-utils, with or without TLS) are NFS; anything else
# at the path, such as the data volume or a root directory, is not EFS.
RAVION_EFS_FSTYPE=$(findmnt -nvo FSTYPE "${efs_mount_path}" 2>/dev/null | head -n 1 || true)
case "$RAVION_EFS_FSTYPE" in
  nfs4 | nfs | efs) ;;
  *)
    echo "${efs_mount_path} holds a $${RAVION_EFS_FSTYPE:-unknown} filesystem, not EFS; refusing to start the app." >&2
    exit 1
    ;;
esac
echo "Storage check: EFS file system mounted at ${efs_mount_path}"
%{ endif ~}
