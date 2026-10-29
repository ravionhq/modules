resource "aws_s3_bucket" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket_prefix = "ravion-cloudtrail-${data.aws_caller_identity.current.account_id}-"
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.cloudtrail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.cloudtrail_kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.cloudtrail_kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.cloudtrail_enabled && var.cloudtrail_log_retention_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  rule {
    id     = "audit-log-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = var.cloudtrail_log_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = var.cloudtrail_log_retention_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.cloudtrail_enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail[0].arn
        Condition = { StringEquals = { "aws:SourceArn" = values(local.cloudtrail_arns) } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = values(local.cloudtrail_arns)
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.cloudtrail[0].arn, "${aws_s3_bucket.cloudtrail[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail, aws_s3_bucket_ownership_controls.cloudtrail]
}
