################################################################################
# Secrets role for the cluster's apps
#
# An app lists its secrets in ravion-app.yaml (`secrets:`), each naming one
# Secrets Manager secret or Parameter Store parameter. The app's own sandbox
# reads them, as this role, just before the app is built or started: the
# sandbox host, an EC2 instance in this account, assumes the role for the
# sandbox and hands it the credentials. The role can read only what
# app_secret_and_parameter_arns lists, whatever an app's file names.
#
# Ravion's own roles are not trusted and never read a secret. Trust is limited
# to this AWS account and, through an aws:PrincipalArn condition, to the role
# of the sandbox hosts of the execution environment the apps run in. That role
# may assume only roles under /rvn-ci/ named rvn-ci-*, which is why this role
# has that path and prefix.
#
# The role always exists, with no policy until something is listed, so every
# sandbox of the cluster holds its credentials from its first start and a
# secret listed later needs no restart.
################################################################################

locals {
  app_secrets_role_name = "rvn-ci-app-secrets-${var.module_instance_id}"

  app_secrets_policy_enabled = length(var.app_secret_and_parameter_arns) > 0

  sandbox_host_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/rvn-sandbox-host-${var.execution_environment_id}"

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
  name        = local.app_secrets_role_name
  path        = "/rvn-ci/"
  description = "What the apps of the ${var.name} App Cluster read their secrets as: the secrets and parameters the cluster lists"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = local.sandbox_host_role_arn
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
  count = local.app_secrets_policy_enabled ? 1 : 0

  name = "read-listed-secrets"
  role = aws_iam_role.app_secrets.id

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
