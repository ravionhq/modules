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

  # Successful build recipes retain references to historical components.
  skip_destroy = true

  tags = merge(local.tags, var.module_instance_id == null ? {} : {
    ModuleId  = var.module_instance_id
    Module    = "compute/ami"
    ManagedBy = "terraform"
  })

  # Create the replacement before retiring the old component from state.
  lifecycle {
    create_before_destroy = true
  }
}
