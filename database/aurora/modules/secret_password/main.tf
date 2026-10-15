# Reads the password out of one version of a Secrets Manager secret holding
# JSON credentials ({"username": ..., "password": ...}), without writing it to
# state. Its own module so tests can override the read: tofu test cannot mock
# an ephemeral resource yet.
ephemeral "aws_secretsmanager_secret_version" "this" {
  secret_id  = var.secret_id
  version_id = var.version_id
}
