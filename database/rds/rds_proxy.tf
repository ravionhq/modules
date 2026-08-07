################################################################################
# RDS Proxy (optional)
################################################################################

module "proxy" {
  count = local.create_proxy ? 1 : 0

  source = "../rds-proxy"

  name          = var.name
  engine_family = local.proxy_engine_family
  vpc_id        = var.vpc_id
  subnet_ids    = var.subnet_ids
  port          = local.port
  tags          = var.tags

  db_instance_identifier = aws_db_instance.this.identifier

  auth = [
    for arn in local.proxy_auth_secret_arns : {
      secret_arn = arn
      iam_auth   = var.proxy_iam_auth_enabled ? "REQUIRED" : "DISABLED"
    }
  ]
  secret_kms_key_arns = local.proxy_secret_kms_key_arns

  tls_requirement_enabled = var.proxy_tls_requirement_enabled
  debug_logging_enabled   = var.proxy_debug_logging_enabled
  idle_client_timeout     = var.proxy_idle_client_timeout

  connection_borrow_timeout    = var.proxy_connection_borrow_timeout
  init_query                   = var.proxy_init_query
  max_connections_percent      = var.proxy_max_connections_percent
  max_idle_connections_percent = var.proxy_max_idle_connections_percent
  session_pinning_filters      = var.proxy_session_pinning_filters

  allowed_security_group_ids = var.allowed_security_group_ids
  allowed_cidr_blocks        = var.allowed_cidr_blocks
}
