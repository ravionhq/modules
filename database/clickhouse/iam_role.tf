################################################################################
# Pod Identity
#
# The ClickHouse pods (the server for the cold tier, the clickhouse-backup
# sidecar for backups) reach S3 through an IAM role bound to their
# ServiceAccount with EKS Pod Identity. No static keys exist anywhere.
#
# The role trusts pods.eks.amazonaws.com pinned to this cluster through
# aws:SourceArn / aws:SourceAccount, and the association limits it to this
# namespace and ServiceAccount. It may read and write the bucket and nothing
# else.
################################################################################

data "aws_iam_policy_document" "pod_identity_trust" {
  count = local.s3_enabled ? 1 : 0

  statement {
    sid     = "AllowEksPodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.cluster_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "clickhouse" {
  count = local.s3_enabled ? 1 : 0

  # Role names are unique per account and the same installation name may exist
  # on several clusters, so the name is a prefix plus a generated suffix.
  name_prefix        = substr("${var.name}-clickhouse-", 0, 38)
  description        = "ClickHouse ${var.namespace}/${var.name} on ${var.cluster_name}: S3 backups and cold tier"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust[0].json

  tags = local.tags

  # The add-on lookup fails the plan when the agent is missing.
  depends_on = [data.aws_eks_addon.pod_identity_agent]
}

data "aws_iam_policy_document" "clickhouse_s3" {
  count = local.s3_enabled ? 1 : 0

  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning"]
    resources = [local.s3_bucket_arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectAttributes",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${local.s3_bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = var.s3_kms_key_arn == null ? [] : [var.s3_kms_key_arn]

    content {
      sid       = "UseBucketKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "clickhouse_s3" {
  count = local.s3_enabled ? 1 : 0

  name   = "s3"
  role   = aws_iam_role.clickhouse[0].id
  policy = data.aws_iam_policy_document.clickhouse_s3[0].json
}

resource "aws_eks_pod_identity_association" "clickhouse" {
  count = local.s3_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.service_account_name
  role_arn        = aws_iam_role.clickhouse[0].arn

  tags = local.tags
}
