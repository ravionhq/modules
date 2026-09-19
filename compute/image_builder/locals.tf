################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/image_builder"
  }

  tags = merge(local.default_tags, var.tags)

  # A form leaves an unused field blank rather than null, so a blank string is
  # read as unset everywhere a caller may leave one.
  parent_image_input          = try(trimspace(var.parent_image), "") == "" ? null : trimspace(var.parent_image)
  parent_image_lookup_enabled = local.parent_image_input == null && var.parent_image_lookup != null
  parent_image                = local.parent_image_lookup_enabled ? data.aws_ami.parent[0].id : local.parent_image_input

  components = [
    for c in var.components : merge(c, {
      data = c.source == "arn" || try(trimspace(c.data), "") == "" ? null : c.data
      arn  = c.source == "inline" || try(trimspace(c.arn), "") == "" ? null : trimspace(c.arn)
    })
  ]

  user_data = try(trimspace(var.user_data), "") == "" ? null : var.user_data

  # Components this module creates, keyed by name. A component is immutable, so
  # each is named by a hash of everything that would force a new one: a changed
  # document is a new component beside the old, never an update in place.
  inline_components = {
    for c in local.components : c.name => merge(c, {
      hash = substr(sha256(jsonencode([c.data, c.platform, c.description, var.recipe_version])), 0, 8)
    }) if c.data != null
  }

  # A public image cannot be backed by an encrypted snapshot.
  root_volume_encrypted = var.root_volume == null ? null : coalesce(var.root_volume.encrypted, !var.public)

  # The recipe is immutable too, and named the same way. The hash covers the
  # inputs rather than the component ARNs, which are unknown until apply.
  recipe_hash = substr(sha256(jsonencode({
    version           = var.recipe_version
    parent_image      = local.parent_image
    components        = [for c in local.components : [c.name, c.data, c.arn, c.platform, c.description, c.parameters]]
    user_data         = local.user_data
    working_directory = var.working_directory
    ssm_uninstall     = var.ssm_agent_uninstall_after_build
    root_volume       = var.root_volume
    encrypted         = local.root_volume_encrypted
  })), 0, 8)

  ami_name = coalesce(var.ami_name, "${var.name}-{{ imagebuilder:buildDate }}")

  all_regions = distinct(concat([local.region], var.distribution_regions))

  launch_permission_enabled = var.public || length(var.launch_account_ids) > 0 || length(var.launch_organization_arns) > 0

  log_prefix = trim(var.log_prefix, "/")
}
