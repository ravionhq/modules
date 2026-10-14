################################################################################
# S3 Bucket Server-Side Encryption Configuration
################################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  region = var.region
  bucket = aws_s3_bucket.this.id

  rule {
    blocked_encryption_types = ["SSE-C"]

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }

    # Enable bucket key for KMS encryption to reduce KMS API call costs
    bucket_key_enabled = local.use_kms_encryption ? var.bucket_key_enabled : null
  }
}
