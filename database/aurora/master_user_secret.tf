################################################################################
# Module-managed master credentials (optional)
#
# Set master_user_secret_name to store the master credentials in a secret with
# a name of your choosing instead of the AWS-managed rds!cluster-* secret. The
# password is ephemeral: generated during each plan/apply and never written to
# state or plan files. It reaches AWS only through the write-only arguments
# here and on the cluster, which are sent together whenever
# master_user_secret_version changes. Nothing rotates it automatically.
################################################################################

# Excludes the characters Aurora rejects in a master password: / @ " and space.
ephemeral "random_password" "master_user" {
  count = local.create_master_user_secret ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master_user" {
  count = local.create_master_user_secret ? 1 : 0

  name        = var.master_user_secret_name
  description = "Master user credentials for the ${var.name} Aurora cluster."
  kms_key_id  = var.master_user_secret_kms_key_id

  tags = local.tags
}

# Same shape as the AWS-managed master user secret (username, password), plus
# connection details known at plan time. RDS Proxy reads username and password.
resource "aws_secretsmanager_secret_version" "master_user" {
  count = local.create_master_user_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.master_user[0].id

  secret_string_wo = jsonencode({
    username = var.master_username
    password = ephemeral.random_password.master_user[0].result
    engine   = local.is_mysql ? "mysql" : "postgres"
    port     = local.port
    dbname   = var.database_name
  })
  secret_string_wo_version = var.master_user_secret_version
}
