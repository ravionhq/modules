################################################################################
# Pod Identity
#
# The workload's AWS identity: an IAM role the pods assume through EKS Pod
# Identity, the EKS analogue of the ECS task role compute/ecs_service creates.
# The Pod Identity Agent on each node hands the AWS SDK short-lived credentials
# for the role, so the pods hold no static keys and the node role stays out of
# reach (the cluster module launches nodes with an IMDS hop limit of 1).
#
# The role trusts pods.eks.amazonaws.com, pinned to this cluster through
# aws:SourceArn / aws:SourceAccount so an association in another cluster of the
# account cannot borrow it. Who may use the role is the association: this
# release's namespace and ServiceAccount, which the rvn-eks-* charts name after
# the release (fullnameOverride) precisely so the association can target it.
################################################################################

locals {
  pod_identity_enabled = var.pod_identity_role_creation_enabled

  # <workload>-task by default, the same shape compute/ecs_service gives its
  # task role. IAM role names are unique per account, so a service that also
  # runs on ECS (or on a second cluster) sets pod_identity_role_name.
  pod_identity_role_name            = local.pod_identity_enabled ? coalesce(var.pod_identity_role_name, "${var.name}-task") : null
  pod_identity_service_account_name = local.pod_identity_enabled ? coalesce(var.pod_identity_service_account_name, var.release_name) : null

  cluster_arn = local.pod_identity_enabled ? "arn:${data.aws_partition.current.partition}:eks:${local.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}" : null

  pod_identity_trust_policy = local.pod_identity_enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEksPodIdentity"
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        ArnEquals    = { "aws:SourceArn" = local.cluster_arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  }) : null
}

# The Pod Identity Agent add-on is what hands the SDK its credentials. Without
# it the role and association apply cleanly and every AWS call in the pods
# fails at runtime, so look the add-on up and let the plan fail instead.
data "aws_eks_addon" "pod_identity_agent" {
  count = local.pod_identity_enabled ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_iam_role" "pod_identity" {
  count = local.pod_identity_enabled ? 1 : 0

  name               = local.pod_identity_role_name
  description        = "EKS Pod Identity role for ${var.name} on ${var.cluster_name}"
  assume_role_policy = local.pod_identity_trust_policy

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(local.pod_identity_role_name) <= 64
      error_message = "The Pod Identity role name '${local.pod_identity_role_name}' exceeds IAM's 64-character limit. Set pod_identity_role_name to a shorter name."
    }
  }
}

resource "aws_iam_role_policy_attachment" "pod_identity_managed" {
  for_each = local.pod_identity_enabled ? toset(var.pod_identity_managed_policy_arns) : toset([])

  role       = aws_iam_role.pod_identity[0].name
  policy_arn = each.value
}

# Policy documents arrive as objects (from YAML or HCL), never as pre-encoded
# JSON strings, matching compute/ecs_service's task_role_inline_policies.
#
# The gate lives inside the for expression, not in a conditional around the
# variable: the variable is typed any, so a populated value is an object whose
# attributes are the policy names, and `enabled ? object : {}` fails OpenTofu
# 1.11's conditional type check ("Inconsistent conditional result types").
resource "aws_iam_role_policy" "pod_identity_inline" {
  for_each = { for name, policy in var.pod_identity_inline_policies : name => policy if local.pod_identity_enabled }

  name   = each.key
  role   = aws_iam_role.pod_identity[0].id
  policy = jsonencode(each.value)
}

resource "aws_eks_pod_identity_association" "this" {
  count = local.pod_identity_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.release_namespace
  service_account = local.pod_identity_service_account_name
  role_arn        = aws_iam_role.pod_identity[0].arn

  tags = local.tags

  lifecycle {
    precondition {
      condition     = data.aws_eks_addon.pod_identity_agent[0].addon_version != ""
      error_message = "Cluster ${var.cluster_name} does not run the eks-pod-identity-agent add-on, so nothing would supply credentials to the pods. Enable pod_identity_agent_enabled on the cluster before creating a Pod Identity role."
    }
  }
}
