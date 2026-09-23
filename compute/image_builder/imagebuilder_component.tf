################################################################################
# Components
#
# One per steps or document component. Referenced components (arn) are used as
# they are.
################################################################################

resource "aws_imagebuilder_component" "this" {
  for_each = local.inline_components

  region      = local.region
  name        = "${var.name}-${each.key}-${each.value.hash}"
  description = each.value.description
  platform    = each.value.platform
  version     = var.component_version
  data        = each.value.data

  tags = local.tags

  # A changed component exists before the old one is deleted, so the next
  # deploy always has a component to build with.
  lifecycle {
    create_before_destroy = true
  }
}
