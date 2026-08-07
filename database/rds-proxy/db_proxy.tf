################################################################################
# RDS Proxy
################################################################################

resource "aws_db_proxy" "this" {
  name           = var.name
  engine_family  = var.engine_family
  role_arn       = local.iam_role_arn
  vpc_subnet_ids = var.subnet_ids

  vpc_security_group_ids = [local.security_group_id]

  require_tls         = var.tls_requirement_enabled
  debug_logging       = var.debug_logging_enabled
  idle_client_timeout = var.idle_client_timeout

  dynamic "auth" {
    for_each = var.auth
    content {
      auth_scheme               = "SECRETS"
      secret_arn                = auth.value.secret_arn
      description               = auth.value.description
      username                  = auth.value.username
      iam_auth                  = auth.value.iam_auth
      client_password_auth_type = auth.value.client_password_auth_type
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = var.security_group_creation_enabled || var.security_group_id != null
      error_message = "security_group_id is required when security_group_creation_enabled is false."
    }

    precondition {
      condition     = var.iam_role_creation_enabled || var.iam_role_arn != null
      error_message = "iam_role_arn is required when iam_role_creation_enabled is false."
    }
  }

  depends_on = [
    aws_iam_role_policy.secrets_access
  ]
}

################################################################################
# Default Target Group (connection pool configuration)
################################################################################

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    connection_borrow_timeout    = var.connection_borrow_timeout
    init_query                   = var.init_query
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    session_pinning_filters      = var.session_pinning_filters
  }
}

################################################################################
# Proxy Target
################################################################################

resource "aws_db_proxy_target" "this" {
  db_proxy_name     = aws_db_proxy.this.name
  target_group_name = aws_db_proxy_default_target_group.this.name

  db_instance_identifier = var.db_instance_identifier
  db_cluster_identifier  = var.db_cluster_identifier

  lifecycle {
    precondition {
      condition     = (var.db_instance_identifier != null) != (var.db_cluster_identifier != null)
      error_message = "Exactly one of db_instance_identifier or db_cluster_identifier must be provided."
    }
  }
}
