################################################################################
# S3 bucket
#
# One bucket, in this account and region, holds two things under separate
# prefixes:
#
#   backup/...               clickhouse-backup archives, one path per shard
#   backup-object-disks/...  copies of cold-tier parts referenced by backups
#   cold/...                 the S3 disk behind the `tiered` policy's `cold`
#                            volume
#
# Created private, versioned and encrypted, with TLS required. Skipped when
# neither backups nor the cold tier is on.
################################################################################

resource "aws_s3_bucket" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket        = var.s3_bucket_name
  bucket_prefix = var.s3_bucket_name == null ? "${var.name}-clickhouse-" : null
  force_destroy = var.s3_force_destroy

  tags = local.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.s3_kms_key_arn
    }
    bucket_key_enabled = var.s3_kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.s3_noncurrent_version_expiration_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "bucket" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this[0].arn,
      "${aws_s3_bucket.this[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = local.s3_enabled && var.s3_bucket_creation_enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
