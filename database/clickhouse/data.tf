################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# The Pod Identity Agent add-on hands ClickHouse and clickhouse-backup their S3
# credentials. Without it the role and association apply cleanly and every S3
# call fails at runtime, so look the add-on up and let the plan fail instead.
data "aws_eks_addon" "pod_identity_agent" {
  count = local.s3_enabled ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

# An existing bucket the caller owns, used for backups and the cold tier.
data "aws_s3_bucket" "existing" {
  count = local.s3_enabled && !var.s3_bucket_creation_enabled ? 1 : 0

  bucket = var.s3_bucket_name
}
