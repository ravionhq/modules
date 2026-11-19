################################################################################
# Secret reader role for the cluster's apps
#
# An app lists its secrets in ravion-app.yaml (`secrets:`), each naming one
# Secrets Manager secret or Parameter Store parameter. Ravion reads them as
# this role just before it builds or starts the app, so it can read only what
# app_secret_and_parameter_arns lists, whatever an app's file names.
#
# Ravion assumes the role by name: rvn-app-secrets-<module instance id>.
# Trust is limited to this AWS account and, through an aws:PrincipalArn
# condition, to the role Ravion deploys with. That role may assume roles
# named rvn-* and holds no access to Secrets Manager of its own.
################################################################################

locals {
  app_secrets_role_name = "rvn-app-secrets-${var.module_instance_id}"

  app_secrets_role_enabled = length(var.app_secret_and_parameter_arns) > 0

  app_secrets_trusted_principal_arns = length(var.app_secrets_trusted_principal_arns) > 0 ? var.app_secrets_trusted_principal_arns : [
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/rvn-*-deployments",
  ]

  # Split the list by service so each statement grants only that service's
  # read.
  app_secretsmanager_arns = [
    for arn in var.app_secret_and_parameter_arns : arn if can(regex("^arn:[^:]*:secretsmanager:", arn))
  ]
  app_ssm_arns = [
    for arn in var.app_secret_and_parameter_arns : arn if can(regex("^arn:[^:]*:ssm:", arn))
  ]
}

resource "aws_iam_role" "app_secrets" {
  count = local.app_secrets_role_enabled ? 1 : 0

  name        = local.app_secrets_role_name
  path        = "/"
  description = "Read by Ravion for the apps of the ${var.name} App Cluster: the secrets and parameters the cluster lists"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:SetSourceIdentity"]
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          ArnLike = {
            "aws:PrincipalArn" = local.app_secrets_trusted_principal_arns
          }
        }
      }
    ]
  })

  tags = local.tags
}

# One statement per service that has something listed. A secret or parameter
# encrypted with a customer-managed key needs the key's decrypt as well; the
# AWS-managed aws/secretsmanager and aws/ssm keys do not.
resource "aws_iam_role_policy" "app_secrets_read" {
  count = local.app_secrets_role_enabled ? 1 : 0

  name = "read-listed-secrets"
  role = aws_iam_role.app_secrets[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.app_secretsmanager_arns) > 0 ? [{
        Sid      = "ReadListedSecrets"
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = local.app_secretsmanager_arns
      }] : [],
      length(local.app_ssm_arns) > 0 ? [{
        Sid      = "ReadListedParameters"
        Action   = ["ssm:GetParameter"]
        Effect   = "Allow"
        Resource = local.app_ssm_arns
      }] : [],
      length(var.app_secret_kms_key_arns) > 0 ? [{
        Sid      = "DecryptWithListedKeys"
        Action   = ["kms:Decrypt"]
        Effect   = "Allow"
        Resource = var.app_secret_kms_key_arns
      }] : [],
    )
  })
}
