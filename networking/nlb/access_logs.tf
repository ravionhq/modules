################################################################################
# Access Logs - S3 Bucket
################################################################################

resource "aws_s3_bucket" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket        = lower("${var.name}-nlb-access-logs-${data.aws_caller_identity.current.account_id}-${local.region}")
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${var.name}-nlb-access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.access_logs_kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.access_logs_kms_key_id
    }
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  versioning_configuration {
    status = var.access_logs_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "access-logs-retention"
    status = "Enabled"

    expiration {
      days = var.access_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowNLBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs[0].arn}/${var.access_logs_prefix != "" ? "${var.access_logs_prefix}/" : ""}AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowNLBLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.access_logs[0].arn
      }
    ]
  })
}
