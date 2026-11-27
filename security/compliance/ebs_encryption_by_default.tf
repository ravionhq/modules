# New EBS volumes and snapshot copies are encrypted with the Region's default
# EBS key. Existing volumes and snapshots are not changed.
resource "aws_ebs_encryption_by_default" "this" {
  for_each = var.ebs_encryption_by_default_enabled ? local.regions : toset([])

  region = each.key

  enabled = true
}
