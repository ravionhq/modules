################################################################################
# Logging
################################################################################

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.logging_destination_arn == null ? 0 : 1

  region = local.region

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [var.logging_destination_arn]

  dynamic "redacted_fields" {
    for_each = var.logging_redacted_fields

    content {
      dynamic "single_header" {
        for_each = redacted_fields.value.type == "header" ? [redacted_fields.value.name] : []
        content {
          name = lower(single_header.value)
        }
      }
      dynamic "query_string" {
        for_each = redacted_fields.value.type == "query_string" ? [1] : []
        content {}
      }
      dynamic "uri_path" {
        for_each = redacted_fields.value.type == "uri_path" ? [1] : []
        content {}
      }
      dynamic "method" {
        for_each = redacted_fields.value.type == "method" ? [1] : []
        content {}
      }
    }
  }
}
