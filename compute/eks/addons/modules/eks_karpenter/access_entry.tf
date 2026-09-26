################################################################################
# Access Entry for Karpenter-Launched Nodes
#
# With authentication_mode = API on the cluster, the node role needs an EC2_LINUX
# access entry to be able to register kubelets. (The legacy aws-auth ConfigMap
# would have done this, but we don't manage that.)
################################################################################

resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = module.node_role.role_arn
  type          = "EC2_LINUX"

  tags = local.tags
}
