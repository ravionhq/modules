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
    Module    = "database/aurora"
  }
  tags = merge(local.default_tags, var.tags)

  # Engine detection
  is_mysql    = var.engine == "aurora-mysql"
  is_postgres = var.engine == "aurora-postgresql"

  # Port defaults based on engine
  default_port = local.is_mysql ? 3306 : 5432
  port         = coalesce(var.port, local.default_port)

  # Parameter group family derivation
  # If not provided, derive from engine and major version
  # Examples: aurora-mysql8.0, aurora-postgresql16
  default_parameter_group_family = (
    var.engine_version != null ? (
      local.is_mysql ? "aurora-mysql${regex("^[0-9]+\\.[0-9]+", var.engine_version)}" :
      local.is_postgres ? "aurora-postgresql${split(".", var.engine_version)[0]}" :
      null
    ) : null
  )

  # CloudWatch logs validation per engine
  # Aurora MySQL: audit, error, general, slowquery
  # Aurora PostgreSQL: postgresql
  valid_log_exports = {
    aurora-mysql      = ["audit", "error", "general", "slowquery"]
    aurora-postgresql = ["postgresql"]
  }

  # Final snapshot identifier (auto-generate if not provided and final snapshots are enabled)
  final_snapshot_identifier = (
    !var.final_snapshot_creation_enabled ? null :
    coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  )

  # Resource creation flags
  create_security_group    = var.security_group_creation_enabled
  create_monitoring_role   = var.monitoring_role_creation_enabled && var.monitoring_interval > 0
  create_cloudwatch_alarms = var.cloudwatch_alarms_creation_enabled
  create_subnet_group      = var.db_subnet_group_name == null

  # Resolved resource names
  db_subnet_group_name         = local.create_subnet_group ? aws_db_subnet_group.this[0].name : var.db_subnet_group_name
  cluster_parameter_group_name = var.cluster_parameter_group_creation_enabled ? aws_rds_cluster_parameter_group.this[0].name : var.cluster_parameter_group_name
  db_parameter_group_name      = var.db_parameter_group_creation_enabled ? aws_db_parameter_group.this[0].name : var.db_parameter_group_name

  # Resolved monitoring role ARN — from created role or provided variable
  monitoring_role_arn = local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn

  # Security group IDs — combines created SG, provided SG, and additional SGs
  vpc_security_group_ids = concat(
    local.create_security_group ? [module.security_group[0].security_group_id] : [],
    var.security_group_id != null ? [var.security_group_id] : [],
    var.security_group_ids,
  )

  # Instance map generation
  # If var.instances is non-empty, use it directly
  # Otherwise, generate from instance_class + reader_count
  is_serverless          = var.serverless_v2_scaling != null
  default_instance_class = local.is_serverless ? "db.serverless" : var.instance_class
  reader_instance_class  = coalesce(var.reader_instance_class, local.default_instance_class)

  generated_instances = merge(
    {
      writer = {
        instance_class               = local.default_instance_class
        availability_zone            = null
        public_access_enabled        = null
        promotion_tier               = 0
        performance_insights_enabled = null
        monitoring_interval          = null
        tags                         = null
      }
    },
    {
      for i in range(var.reader_count) : "reader-${i + 1}" => {
        instance_class               = local.reader_instance_class
        availability_zone            = null
        public_access_enabled        = null
        promotion_tier               = i + 1
        performance_insights_enabled = null
        monitoring_interval          = null
        tags                         = null
      }
    }
  )

  instances = length(var.instances) > 0 ? var.instances : local.generated_instances

  # RDS Proxy
  create_proxy        = var.proxy_creation_enabled
  proxy_engine_family = local.is_mysql ? "MYSQL" : "POSTGRESQL"
  proxy_auth_secret_arns = (
    length(var.proxy_auth_secret_arns) > 0 ? var.proxy_auth_secret_arns :
    var.master_user_password_management_enabled ? [for s in aws_rds_cluster.this.master_user_secret : s.secret_arn] : []
  )
  proxy_secret_kms_key_arns = distinct(concat(
    var.proxy_secret_kms_key_arns,
    try(startswith(var.master_user_secret_kms_key_id, "arn:"), false) ? [var.master_user_secret_kms_key_id] : []
  ))
}
