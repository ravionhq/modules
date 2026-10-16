################################################################################
# Module-managed master credentials (optional)
#
# Set master_user_secret_name to store the master credentials in a secret with
# a name of your choosing instead of the AWS-managed rds!cluster-* secret. The
# password never reaches state or plan files: it is generated ephemerally and
# reaches AWS only through write-only arguments. Nothing rotates it
# automatically.
#
# The secret is the one source of the password. A new password is written to
# the secret only, when the secret version is created: on first apply, when
# master_user_secret_version changes, or when the secret is replaced (a new
# name). The cluster then reads the password back from the secret and rewrites
# its own whenever the secret's version changes, so every path, including a
# retry after only one of the two writes succeeded and a replaced cluster,
# ends with the cluster and the secret holding the same password.
################################################################################

# Excludes the characters Aurora rejects in a master password: / @ " and space.
ephemeral "aws_secretsmanager_random_password" "master_user" {
  count = local.create_master_user_secret ? 1 : 0

  password_length            = 32
  exclude_characters         = "/@\""
  include_space              = false
  require_each_included_type = true
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
    password = ephemeral.aws_secretsmanager_random_password.master_user[0].random_password
    engine   = local.is_mysql ? "mysql" : "postgres"
    port     = local.port
    dbname   = var.database_name
  })
  secret_string_wo_version = var.master_user_secret_version
}

# The password as the secret holds it, read at apply time for the cluster.
module "master_user_secret_password" {
  source = "./modules/secret_password"
  count  = local.create_master_user_secret ? 1 : 0

  secret_id  = aws_secretsmanager_secret.master_user[0].id
  version_id = aws_secretsmanager_secret_version.master_user[0].version_id
}
