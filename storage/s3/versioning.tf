################################################################################
# S3 Bucket Versioning Configuration
################################################################################

resource "aws_s3_bucket_versioning" "this" {
  region = var.region
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}
