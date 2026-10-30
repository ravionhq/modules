################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_eks_cluster" "current" {
  count = local.track_ami_release && var.kubernetes_version == null ? 1 : 0

  name = var.cluster_name
}

data "aws_ssm_parameter" "ami_release" {
  count = local.track_ami_release ? 1 : 0

  name = format(local.ami_release_parameters[var.ami_type], local.ami_kubernetes_version)
}
