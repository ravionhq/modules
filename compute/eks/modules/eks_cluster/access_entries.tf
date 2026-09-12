################################################################################
# EKS Access Entries
#
# Replaces the legacy aws-auth ConfigMap. Each entry maps an IAM principal to a
# cluster identity, optionally with one or more access policies. STANDARD type
# is used for human/automation principals; the EC2_LINUX / FARGATE_LINUX types
# exist for node roles and are typically managed by the node_group / karpenter
# modules.
################################################################################

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups
  user_name         = each.value.user_name

  tags = local.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = merge([
    for entry_key, entry in var.access_entries : {
      for assoc_key, assoc in entry.policy_associations :
      "${entry_key}:${assoc_key}" => {
        entry_key        = entry_key
        policy_arn       = assoc.policy_arn
        scope_type       = assoc.access_scope_type
        scope_namespaces = assoc.access_scope_namespaces
      }
    }
  ]...)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.value.entry_key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.scope_type == "namespace" ? each.value.scope_namespaces : null
  }
}
