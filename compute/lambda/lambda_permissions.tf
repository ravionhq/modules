################################################################################
# Lambda Permissions
################################################################################

resource "aws_lambda_permission" "this" {
  for_each = local.permissions_map

  statement_id  = coalesce(try(each.value.statement_id, null), "AllowExecutionFrom${each.key}")
  action        = coalesce(try(each.value.action, null), "lambda:InvokeFunction")
  function_name = aws_lambda_function.this.function_name
  principal     = each.value.principal

  source_arn             = try(each.value.source_arn, null)
  source_account         = try(each.value.source_account, null)
  event_source_token     = try(each.value.event_source_token, null)
  function_url_auth_type = try(each.value.function_url_auth_type, null)
  qualifier = try(each.value.qualifier, null) != null ? each.value.qualifier : (
    try(each.value.function_url_auth_type, null) != null || try(each.value.action, null) == "lambda:InvokeFunctionUrl" ? aws_lambda_alias.this["live"].name : null
  )
  principal_org_id = try(each.value.principal_org_id, null)
}
