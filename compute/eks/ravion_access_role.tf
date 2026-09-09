resource "aws_iam_role" "ravion_access_read" {
  name               = "${local.ravion_access_name}-read"
  assume_role_policy = local.ravion_access_assume_role_policy
  tags               = local.ravion_access_tags
}

resource "aws_eks_access_entry" "ravion_access_read" {
  cluster_name      = module.cluster.cluster_name
  principal_arn     = aws_iam_role.ravion_access_read.arn
  type              = "STANDARD"
  kubernetes_groups = ["ravion:readers"]
  tags              = local.ravion_access_tags
}

resource "aws_eks_access_policy_association" "ravion_access_read" {
  cluster_name  = module.cluster.cluster_name
  principal_arn = aws_eks_access_entry.ravion_access_read.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  access_scope {
    type = "cluster"
  }
}

data "aws_iam_policy_document" "ravion_access" {
  statement {
    sid       = "DescribeThisCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [module.cluster.cluster_arn]
  }
}

resource "aws_iam_role_policy" "ravion_access_read" {
  name   = "eks-ssm-access"
  role   = aws_iam_role.ravion_access_read.id
  policy = data.aws_iam_policy_document.ravion_access.json
}
