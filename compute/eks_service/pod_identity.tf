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

  # <cluster>-<workload>-task by default: unique across clusters in the account
  # and distinct from the <workload>-task role the ECS module creates, so the
  # same service can run on both during a migration.
  pod_identity_role_name            = local.pod_identity_enabled ? coalesce(var.pod_identity_role_name, "${var.cluster_name}-${var.name}-task") : null
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
resource "aws_iam_role_policy" "pod_identity_inline" {
  for_each = local.pod_identity_enabled ? var.pod_identity_inline_policies : {}

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
}
