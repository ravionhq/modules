################################################################################
# Distribution Configuration
#
# The same name, tags and launch permission in the build region and every
# distribution region.
################################################################################

resource "aws_imagebuilder_distribution_configuration" "this" {
  region      = local.region
  name        = var.name
  description = var.description

  dynamic "distribution" {
    for_each = local.all_regions

    content {
      region = distribution.value

      ami_distribution_configuration {
        name        = local.ami_name
        description = var.ami_description
        ami_tags    = merge(local.tags, var.ami_tags)

        dynamic "launch_permission" {
          for_each = local.launch_permission_enabled ? [1] : []

          content {
            user_groups       = var.public ? ["all"] : null
            user_ids          = length(var.launch_account_ids) > 0 ? var.launch_account_ids : null
            organization_arns = length(var.launch_organization_arns) > 0 ? var.launch_organization_arns : null
          }
        }
      }
    }
  }

  tags = local.tags

  # A public distribution fails at build time, not at apply, in a region that
  # still blocks public sharing.
  depends_on = [aws_ec2_image_block_public_access.this]
}

################################################################################
# Public sharing
#
# New accounts block public AMI sharing per region. The setting is account-wide
# for the region, and removing this resource leaves it as it is.
################################################################################

resource "aws_ec2_image_block_public_access" "this" {
  for_each = var.public && var.manage_image_block_public_access ? toset(local.all_regions) : toset([])

  region = each.value
  state  = "unblocked"
}
