################################################################################
# Proxy IAM Role
#
# Allows the RDS Proxy service to read database credentials from Secrets
# Manager (and decrypt them when a customer-managed KMS key is used).
################################################################################

resource "aws_iam_role" "this" {
  count = local.create_iam_role ? 1 : 0

  name = "${var.name}-rds-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "secrets_access" {
  count = local.create_iam_role ? 1 : 0

  name = "secrets-access"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "GetSecretValue"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = local.auth_secret_arns
        }
      ],
      length(var.secret_kms_key_arns) > 0 ? [
        {
          Sid      = "DecryptSecrets"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = var.secret_kms_key_arns
          Condition = {
            StringEquals = {
              "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com"
            }
          }
        }
      ] : []
    )
  })
}
