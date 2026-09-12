################################################################################
# External Secrets Operator — AWS-side resources (optional add-on)
#
# Pod Identity role for the ESO controller. The controller resolves AWS
# credentials through the SDK default credential chain, which the Pod Identity
# Agent populates, so the ClusterSecretStores carry no `auth` block and no
# static credentials exist anywhere in the cluster.
#
# Permissions are read-only against Secrets Manager and SSM Parameter Store.
# The Helm-side install lives in external_secrets.tf.
################################################################################

locals {
  # Secrets are created by workloads long after this stack applies, so the
  # module cannot enumerate them. The default is therefore read of every
  # secret and parameter in this account and region — the tightest scope that
  # still works without knowing the ARNs up front. Set eso_secret_and_parameter_arns to
  # narrow it (and to reach other regions or accounts).
  eso_default_secretsmanager_arns = [
    "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:*",
  ]

  eso_default_ssm_arns = [
    "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/*",
  ]

  # Split the caller's list by service so each statement only grants that
  # service's actions. A list with entries for one service only omits the
  # other service's statement entirely.
  eso_secretsmanager_arns = length(var.eso_secret_and_parameter_arns) > 0 ? [
    for arn in var.eso_secret_and_parameter_arns : arn if can(regex("^arn:[^:]*:secretsmanager:", arn))
  ] : local.eso_default_secretsmanager_arns

  eso_ssm_arns = length(var.eso_secret_and_parameter_arns) > 0 ? [
    for arn in var.eso_secret_and_parameter_arns : arn if can(regex("^arn:[^:]*:ssm:", arn))
  ] : local.eso_default_ssm_arns
}

data "aws_iam_policy_document" "external_secrets" {
  count = var.eso_enabled ? 1 : 0

  dynamic "statement" {
    for_each = length(local.eso_secretsmanager_arns) > 0 ? [1] : []

    content {
      sid    = "ReadSecretsManagerSecrets"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = local.eso_secretsmanager_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.eso_ssm_arns) > 0 ? [1] : []

    content {
      sid    = "ReadParameterStoreParameters"
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      resources = local.eso_ssm_arns
    }
  }

  # Secrets encrypted with a customer-managed key need an explicit decrypt
  # grant; the AWS-managed aws/secretsmanager and aws/ssm keys do not.
  dynamic "statement" {
    for_each = length(var.eso_kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptCustomerManagedKeys"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.eso_kms_key_arns
    }
  }
}

module "external_secrets_role" {
  count = var.eso_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-external-secrets"
  description = "External Secrets Operator Pod Identity role for ${var.cluster_name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "secret-read" = data.aws_iam_policy_document.external_secrets[0].json
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  count = var.eso_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account
  role_arn        = module.external_secrets_role[0].role_arn

  tags = local.tags
}
