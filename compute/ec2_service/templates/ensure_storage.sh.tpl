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
echo "Storage check: data volume mounted at ${data_volume_mount_path}"
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
echo "Storage check: EFS file system mounted at ${efs_mount_path}"
%{ endif ~}
