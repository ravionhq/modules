################################################################################
# Aliases
################################################################################

resource "aws_lambda_alias" "this" {
  for_each = local.aliases

  name             = each.key
  description      = try(each.value.description, null)
  function_name    = aws_lambda_function.this.function_name
  function_version = coalesce(try(each.value.function_version, null), aws_lambda_function.this.version)

  # After creation Ravion owns the pointer, including explicit rollbacks.
  lifecycle {
    ignore_changes = [function_version]
  }

  dynamic "routing_config" {
    for_each = length(try(each.value.routing_additional_version_weights, {})) > 0 ? [1] : []
    content {
      additional_version_weights = each.value.routing_additional_version_weights
    }
  }
}
