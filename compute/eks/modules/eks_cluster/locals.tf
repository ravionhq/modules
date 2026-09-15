locals {
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/modules/eks_cluster"
  }

  tags = merge(local.default_tags, var.tags)

  oidc_issuer      = aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_issuer_host = replace(local.oidc_issuer, "https://", "")

  enable_logging = length(var.enabled_cluster_log_types) > 0

  secrets_kms_key_arn = (
    var.secrets_kms_key_arn != null
    ? var.secrets_kms_key_arn
    : (var.secrets_encryption_enabled ? module.secrets_kms[0].key_arn : null)
  )

  pod_identity_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
