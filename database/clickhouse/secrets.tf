################################################################################
# User credentials
#
# One Secrets Manager secret per user: admin, writer, reader and the operator's
# own user. Each password is generated ephemerally and reaches AWS only
# through write-only arguments, so it is never in state or plan files.
#
# The External Secrets Operator copies each secret into a Kubernetes Secret
# (see charts/clickhouse-secrets). ClickHouse reads the passwords from those
# Secrets as environment variables, so they appear in no Helm values and no
# ConfigMap. Applications read the same Secrets Manager secrets, which also
# carry the connection details.
#
# A new password is written when password_version changes. Nothing rotates
# them automatically.
################################################################################

ephemeral "aws_secretsmanager_random_password" "user" {
  for_each = local.users

  password_length = 40
  # Characters that need escaping in URLs, XML or shell are left out so the
  # password works unquoted in a DSN.
  exclude_punctuation        = true
  include_space              = false
  require_each_included_type = true
}

resource "aws_secretsmanager_secret" "user" {
  for_each = local.users

  name                    = "${local.secrets_name_prefix}/${each.key}"
  description             = "ClickHouse ${each.key} user for ${var.namespace}/${var.name} on ${var.cluster_name}."
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.secrets_recovery_window_in_days

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "user" {
  for_each = local.users

  secret_id = aws_secretsmanager_secret.user[each.key].id

  secret_string_wo = jsonencode({
    username    = each.value.username
    password    = ephemeral.aws_secretsmanager_random_password.user[each.key].random_password
    host        = local.service_host
    http_port   = 8123
    native_port = 9000
    database    = coalesce(var.database_name, "default")
    cluster     = local.cluster_layout_name
  })
  secret_string_wo_version = var.password_version
}
