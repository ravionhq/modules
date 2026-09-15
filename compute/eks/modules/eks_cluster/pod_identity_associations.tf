################################################################################
# Caller-Supplied Pod Identity Associations
#
# Lets consumers wire their own service accounts to IAM roles without standing
# up an aws_eks_pod_identity_association resource themselves. Roles must be
# pre-created with a trust policy that allows pods.eks.amazonaws.com.
################################################################################

resource "aws_eks_pod_identity_association" "extra" {
  for_each = var.pod_identity_associations

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn

  tags = local.tags
}
