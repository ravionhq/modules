################################################################################
# Public AMI Sharing
################################################################################

# AWS blocks public AMI sharing per region by default, which refuses a deploy
# that grants launch permission all. Every region a release lands in allows it.
resource "aws_ec2_image_block_public_access" "this" {
  for_each = var.public_sharing_enabled ? toset(concat([local.region], var.distribution_regions)) : toset([])

  region = each.value
  state  = "unblocked"
}
