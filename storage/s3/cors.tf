################################################################################
# S3 Bucket CORS Configuration
################################################################################

resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.create_cors_configuration ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      id              = cors_rule.value.id
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}
