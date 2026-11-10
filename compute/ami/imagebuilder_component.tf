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

    # A document the module writes from steps is held to Image Builder's limit
    # too, with the component named, before the provider refuses it.
    precondition {
      condition     = length(each.value.data) <= 16000
      error_message = "Component ${each.key}'s document is ${length(each.value.data)} characters; Image Builder takes at most 16,000. Move steps into another component."
    }
  }
}
