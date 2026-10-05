################################################################################
# Function URL
################################################################################

resource "aws_lambda_function_url" "this" {
  count = var.function_url_enabled ? 1 : 0

  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.this["live"].name
  authorization_type = var.function_url_auth_type
  invoke_mode        = var.function_url_invoke_mode

  dynamic "cors" {
    for_each = var.function_url_cors != null ? [var.function_url_cors] : []
    content {
      allow_credentials = try(cors.value.allow_credentials, null)
      allow_headers     = try(cors.value.allow_headers, null)
      allow_methods     = try(cors.value.allow_methods, null)
      allow_origins     = try(cors.value.allow_origins, null)
      expose_headers    = try(cors.value.expose_headers, null)
      max_age           = try(cors.value.max_age, null)
    }
  }
}
