locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/rds"
  }
  tags = merge(local.default_tags, var.tags)

  # Engine detection
  is_mysql     = var.engine == "mysql"
  is_postgres  = var.engine == "postgres"
  is_mariadb   = var.engine == "mariadb"
  is_oracle    = startswith(var.engine, "oracle-")
  is_sqlserver = startswith(var.engine, "sqlserver-")

  sqlserver_engine_version_parts = var.engine_major_version != null ? split(".", var.engine_major_version) : []
  sqlserver_engine_major         = var.engine_major_version != null ? local.sqlserver_engine_version_parts[0] : null
  sqlserver_engine_minor         = var.engine_major_version != null && length(local.sqlserver_engine_version_parts) > 1 ? local.sqlserver_engine_version_parts[1] : "0"
  sqlserver_parameter_version    = var.engine_major_version != null ? "${local.sqlserver_engine_major}.${substr("${local.sqlserver_engine_minor}0", 0, 1)}" : null
  sqlserver_option_version       = var.engine_major_version != null ? "${local.sqlserver_engine_major}.${substr("${local.sqlserver_engine_minor}00", 0, 2)}" : null

  # Port defaults based on engine
  default_port = (
    local.is_mysql || local.is_mariadb ? 3306 :
    local.is_postgres ? 5432 :
    local.is_oracle ? 1521 :
    local.is_sqlserver ? 1433 :
    3306
  )
  port = coalesce(var.port, local.default_port)

  engine_version = (
    var.engine_major_version != null ? (
      var.engine_minor_version != null ? "${var.engine_major_version}.${var.engine_minor_version}" : var.engine_major_version
    ) : null
  )

  # Parameter group family derivation
  # If not provided, derive from engine and major version
  # Examples: mysql8.0, postgres15, mariadb10.6, oracle-ee-19, sqlserver-ee-15.0
  default_parameter_group_family = (
    var.engine_major_version != null ? (
      local.is_mysql ? "mysql${regex("^[0-9]+\\.[0-9]+", var.engine_major_version)}" :
      local.is_postgres ? "postgres${split(".", var.engine_major_version)[0]}" :
      local.is_mariadb ? "mariadb${regex("^[0-9]+\\.[0-9]+", var.engine_major_version)}" :
      local.is_oracle ? "${var.engine}-${split(".", var.engine_major_version)[0]}" :
      local.is_sqlserver ? "${var.engine}-${local.sqlserver_parameter_version}" :
      null
      ) : (
      local.is_mysql ? "mysql8.0" :
      local.is_postgres ? "postgres16" :
      local.is_mariadb ? "mariadb10.6" :
      local.is_oracle ? "${var.engine}-19" :
      local.is_sqlserver ? "${var.engine}-15.0" :
      null
    )
  )
  parameter_group_family = (
    var.parameter_group_family != null
    ? var.parameter_group_family
    : local.default_parameter_group_family
  )
  parameter_group_name = "rds-${var.name}"

  # Option group major engine version derivation
  # For Oracle: 19, 21
  # For SQL Server: 15.00, 16.00
  default_option_group_engine_version = (
    var.engine_major_version != null ? (
      local.is_oracle ? split(".", var.engine_major_version)[0] :
      local.is_sqlserver ? local.sqlserver_option_version :
      split(".", var.engine_major_version)[0]
      ) : (
      local.is_oracle ? "19" :
      local.is_sqlserver ? "15.00" :
      null
    )
  )
  option_group_engine_version = (
    var.option_group_engine_version != null
    ? var.option_group_engine_version
    : local.default_option_group_engine_version
  )

  # Resource creation flags
  create_security_group  = var.security_group_creation_enabled
  create_parameter_group = var.parameter_group_creation_enabled
  create_option_group    = var.option_group_creation_enabled && (local.is_oracle || local.is_sqlserver)
  create_monitoring_role = var.monitoring_role_creation_enabled && var.monitoring_interval > 0

  # Read replica creation
  create_read_replicas = var.read_replica_creation_enabled && var.read_replica_count > 0
  read_replica_count   = local.create_read_replicas ? var.read_replica_count : 0

  # Read replica instance class (defaults to primary if not specified)
  read_replica_instance_class = coalesce(var.read_replica_instance_class, var.instance_class)

  # CloudWatch alarm creation
  create_cloudwatch_alarms = var.cloudwatch_alarms_creation_enabled

  # CloudWatch logs validation per engine
  # MySQL: audit, error, general, slowquery
  # PostgreSQL: postgresql, upgrade
  # MariaDB: audit, error, general, slowquery
  # Oracle: alert, audit, listener, trace, oemagent
  # SQL Server: agent, error
  valid_log_exports = {
    mysql     = ["audit", "error", "general", "slowquery"]
    postgres  = ["postgresql", "upgrade"]
    mariadb   = ["audit", "error", "general", "slowquery"]
    oracle    = ["alert", "audit", "listener", "trace", "oemagent"]
    sqlserver = ["agent", "error"]
  }
  engine_log_type = (
    local.is_mysql ? "mysql" :
    local.is_postgres ? "postgres" :
    local.is_mariadb ? "mariadb" :
    local.is_oracle ? "oracle" :
    local.is_sqlserver ? "sqlserver" :
    "mysql"
  )

  # Final snapshot identifier (auto-generate if final_snapshot_creation_enabled is true)
  final_snapshot_identifier = (
    !var.final_snapshot_creation_enabled ? null :
    coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  )

  # IAM database authentication is only supported for MySQL and PostgreSQL
  iam_database_authentication_enabled = var.iam_database_authentication_enabled && (local.is_mysql || local.is_postgres)

  # DB name handling - SQL Server doesn't support db_name at creation time
  db_name = local.is_sqlserver ? null : var.db_name

  # RDS Proxy
  create_proxy = var.proxy_creation_enabled
  proxy_engine_family = (
    local.is_postgres ? "POSTGRESQL" :
    local.is_sqlserver ? "SQLSERVER" :
    "MYSQL"
  )
  proxy_auth_secret_arns = (
    length(var.proxy_auth_secret_arns) > 0 ? var.proxy_auth_secret_arns :
    var.master_user_password_management_enabled ? [for s in aws_db_instance.this.master_user_secret : s.secret_arn] : []
  )
  proxy_secret_kms_key_arns = distinct(concat(
    var.proxy_secret_kms_key_arns,
    try(startswith(var.master_user_secret_kms_key_id, "arn:"), false) ? [var.master_user_secret_kms_key_id] : []
  ))
}
