################################################################################
# Components
#
# One per inline document. Referenced components (arn) are used as they are.
################################################################################

resource "aws_imagebuilder_component" "this" {
  for_each = local.inline_components

  region      = local.region
  name        = "${var.name}-${each.key}-${each.value.hash}"
  description = each.value.description
  platform    = each.value.platform
  version     = var.recipe_version
  data        = each.value.data

  tags = local.tags

  # The new component exists before the recipe moves to it and the old one is
  # deleted only after nothing references it.
  lifecycle {
    create_before_destroy = true
  }
}
