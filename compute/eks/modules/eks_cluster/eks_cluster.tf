################################################################################
# EKS Cluster
################################################################################

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = module.cluster_role.role_arn

  deletion_protection = var.deletion_protection_enabled

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access_enabled
    endpoint_private_access = var.endpoint_private_access_enabled
    public_access_cidrs     = var.endpoint_public_access_enabled ? var.public_access_cidrs : null
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.ip_family == "ipv4" ? var.service_ipv4_cidr : null
    ip_family         = var.ip_family
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions_enabled
  }

  dynamic "encryption_config" {
    for_each = local.secrets_kms_key_arn != null ? [1] : []
    content {
      provider {
        key_arn = local.secrets_kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    # Replacing a cluster deletes every workload and volume on it. With
    # deletion protection on, refuse any plan that would destroy or replace
    # the cluster at PLAN time. AWS-side deletion protection alone is not
    # enough: a replacement fails only when it reaches the cluster, after
    # every change ordered ahead of it (such as a node group replacement) has
    # already been applied. To destroy the cluster, turn deletion protection
    # off first, exactly as AWS requires.
    prevent_destroy = var.deletion_protection_enabled

    # AWS reads the bootstrap flag only at creation and the provider marks it
    # ForceNew, so a changed default must not plan a replacement of every
    # existing cluster.
    ignore_changes = [access_config[0].bootstrap_cluster_creator_admin_permissions]

    precondition {
      condition     = alltrue([for subnet in data.aws_subnet.selected : subnet.vpc_id == var.vpc_id])
      error_message = "All subnet_ids must belong to vpc_id."
    }

    # In API authentication mode nothing but access entries can reach the
    # Kubernetes API. Refuse to create a cluster nobody can administer, which
    # would otherwise need an out-of-band eks:CreateAccessEntry to recover.
    precondition {
      condition     = local.cluster_has_an_administrator
      error_message = "The cluster would have no administrator: bootstrap_cluster_creator_admin_permissions_enabled is false and no access_entries entry carries a policy association or Kubernetes group. Add an access entry for an operator role, enable the bootstrap creator admin, or set cluster_admin_access_managed_externally when you register an admin entry yourself."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    module.cluster_role,
  ]
}
