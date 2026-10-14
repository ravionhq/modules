################################################################################
# Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "this" {
  count = local.use_secrets_manager ? 1 : 0

  name                    = local.secret_name
  description             = local.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  dynamic "replica" {
    for_each = toset(var.replica_regions)

    content {
      region     = replica.value
      kms_key_id = local.replica_kms_key_id
    }
  }

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  count = local.use_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.this[0].id

  secret_string_wo         = ephemeral.random_password.this.result
  secret_string_wo_version = var.rotation_version
}
