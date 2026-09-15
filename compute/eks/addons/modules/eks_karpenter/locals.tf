locals {
  region     = data.aws_region.current.region
  partition  = var.partition != null ? var.partition : data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks/addons/modules/eks_karpenter"
  }

  tags = merge(local.default_tags, var.tags)

  queue_name = coalesce(var.interruption_queue_name, "karpenter-${var.cluster_name}")

  pod_identity_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
