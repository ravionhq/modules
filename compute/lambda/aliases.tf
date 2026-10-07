################################################################################
# Aliases
################################################################################

# Keep user-defined aliases at their existing addresses and Terraform-managed.
resource "aws_lambda_alias" "this" {
  for_each = { for name, alias in local.aliases : name => alias if name != "live" }

  name             = each.key
  description      = try(each.value.description, null)
  function_name    = aws_lambda_function.this.function_name
  function_version = coalesce(try(each.value.function_version, null), aws_lambda_function.this.version)

  dynamic "routing_config" {
    for_each = length(try(each.value.routing_additional_version_weights, {})) > 0 ? [1] : []
    content {
      additional_version_weights = each.value.routing_additional_version_weights
    }
  }
}

# Lifecycle ignore_changes is static, so only the deployment alias belongs here.
resource "aws_lambda_alias" "live" {
  for_each = { for name, alias in local.aliases : name => alias if name == "live" }

  name             = each.key
  description      = try(each.value.description, null)
  function_name    = aws_lambda_function.this.function_name
  function_version = coalesce(try(each.value.function_version, null), aws_lambda_function.this.version)

  # After creation Ravion owns this pointer, including explicit rollbacks.
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

# Preserve the existing live alias without destroying/recreating it on upgrade.
moved {
  from = aws_lambda_alias.this["live"]
  to   = aws_lambda_alias.live["live"]
}
