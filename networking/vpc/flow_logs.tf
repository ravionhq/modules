################################################################################
# VPC Flow Logs - CloudWatch
################################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.name}"
  retention_in_days = var.flow_logs_retention_days == 0 ? null : var.flow_logs_retention_days

  tags = merge(local.tags, {
    Name = "${var.name}-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name = "${var.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name = "${var.name}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Effect = "Allow"
        Resource = [
          aws_cloudwatch_log_group.flow_logs[0].arn,
          "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
        ]
      }
    ]
  })
}

resource "aws_flow_log" "cloudwatch" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(local.tags, {
    Name = "${var.name}-flow-log"
  })
}

################################################################################
# VPC Flow Logs - S3
################################################################################

resource "aws_s3_bucket" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket        = "${var.name}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.flow_logs_kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.flow_logs_kms_key_id
    }
  }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = var.flow_logs_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "flow-logs-retention"
    status = "Enabled"

    expiration {
      days = var.flow_logs_retention_days == 0 ? 365 : var.flow_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.flow_logs[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.flow_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

resource "aws_flow_log" "s3" {
  count = local.create_flow_log_s3 ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "s3"
  log_destination          = local.flow_log_s3_bucket_arn
  max_aggregation_interval = 60

  tags = merge(local.tags, {
    Name = "${var.name}-flow-log"
  })

  depends_on = [aws_s3_bucket_policy.flow_logs]
}

