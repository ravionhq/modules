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

locals {
  # An access entry only grants access when it carries a policy association
  # or maps to Kubernetes groups; a bare entry authenticates but authorizes
  # nothing.
  granting_access_entries = [
    for key, entry in var.access_entries : key
    if length(entry.policy_associations) > 0 || length(entry.kubernetes_groups) > 0
  ]

  cluster_has_an_administrator = (
    var.bootstrap_cluster_creator_admin_permissions_enabled
    || var.cluster_admin_access_managed_externally
    || length(local.granting_access_entries) > 0
  )
}

locals {
  # Without a warm IP target the CNI keeps a whole spare ENI of IPs on every
  # node, used or not. In a small subnet that reserve runs it dry, and pods on
  # the next node fail to get an address.
  vpc_cni_env = {
    for name, value in {
      WARM_IP_TARGET    = var.vpc_cni_warm_ip_target
      MINIMUM_IP_TARGET = var.vpc_cni_minimum_ip_target
    } : name => tostring(value) if value != null
  }

  # The CNI add-on schema takes enableNetworkPolicy and env values as strings.
  # An explicit configuration document wins untouched, matching the other
  # add-ons.
  vpc_cni_generated_configuration = merge(
    { for key, value in { enableNetworkPolicy = "true" } : key => value if var.network_policy_enabled },
    { for key, value in { env = local.vpc_cni_env } : key => value if length(local.vpc_cni_env) > 0 },
  )
  vpc_cni_addon_configuration_values = (
    var.vpc_cni_addon_configuration_values != null
    ? var.vpc_cni_addon_configuration_values
    : (length(local.vpc_cni_generated_configuration) > 0 ? jsonencode(local.vpc_cni_generated_configuration) : null)
  )
}
