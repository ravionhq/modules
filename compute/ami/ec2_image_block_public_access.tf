################################################################################
# Public AMI Sharing
################################################################################

# AWS blocks public AMI sharing per region by default, which refuses a deploy
# that grants launch permission all. Every region a release lands in takes the
# chosen state. The provider's delete leaves the account's state unchanged, so
# block-new-sharing is how the block comes back.
resource "aws_ec2_image_block_public_access" "this" {
  for_each = var.image_block_public_access == null ? toset([]) : toset(concat([local.region], var.distribution_regions))

  region = each.value
  state  = var.image_block_public_access
}
