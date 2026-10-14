# Public URLs require both permissions on the alias, not on $LATEST.
resource "aws_lambda_permission" "function_url" {
  count = var.function_url_enabled && var.function_url_auth_type == "NONE" ? 1 : 0

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  qualifier              = aws_lambda_alias.live["live"].name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "function_url_invoke" {
  count = var.function_url_enabled && var.function_url_auth_type == "NONE" ? 1 : 0

  statement_id             = "AllowPublicInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.this.function_name
  qualifier                = aws_lambda_alias.live["live"].name
  principal                = "*"
  invoked_via_function_url = true
}
