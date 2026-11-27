# The account default applies only to instances launched without their own
# metadata options; a launch template or instance that sets them keeps its own.
# Running instances are not changed.
resource "aws_ec2_instance_metadata_defaults" "this" {
  for_each = var.imdsv2_default_enabled ? local.regions : toset([])

  region = each.key

  http_tokens = "required"
}
