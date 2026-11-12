# First-boot formatting of a brand-new data volume. Included only in user
# data, never in the deploy document; needs data_volume_mount.sh.tpl first.
# First boot: give a brand-new data volume an XFS filesystem with the
# Ravion label. Never formats a disk that has a filesystem or partitions.
ravion_format_new_data_volume() {
  local disk="" candidate candidates="" count=0
  if [ -n "$(ravion_labeled_disks)" ]; then
    return 0
  fi
  disk=$(ravion_linked_disk)
  if [ -n "$disk" ]; then
    if ! ravion_is_blank "$disk"; then
      return 0
    fi
  else
    # Without a device link the blank disk can't be told apart from an
    # instance-store disk. If another disk already holds a filesystem, it is
    # the likelier data volume (one from an older release has no label), so
    # format nothing: a fresh label would make discovery prefer the empty disk.
    for candidate in $(ravion_other_disks); do
      if ravion_has_data_fs "$candidate"; then
        echo "Data volume: $candidate already has a filesystem; not formatting another disk" >&2
        return 0
      fi
    done
    for candidate in $(ravion_other_disks); do
      if ravion_is_blank "$candidate" && ! ravion_is_mounted "$candidate"; then
        candidates="$candidates $candidate"
        count=$((count + 1))
      fi
    done
    if [ "$count" -gt 1 ]; then
      echo "Data volume: several blank disks found ($candidates ); not formatting any of them" >&2
      return 0
    fi
    disk="$${candidates# }"
  fi
  if [ -z "$disk" ]; then
    return 0
  fi
  echo "Data volume: formatting new disk $disk"
  mkfs -t xfs -L "$RAVION_DATA_LABEL" "$disk"
}
