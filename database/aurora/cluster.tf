################################################################################
# Global Cluster (optional)
################################################################################

resource "aws_rds_global_cluster" "this" {
  count = var.global_cluster_creation_enabled ? 1 : 0

  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  storage_encrypted         = var.storage_encryption_enabled
  database_name             = var.database_name
  deletion_protection       = var.deletion_protection_enabled
}

################################################################################
# Aurora Cluster
################################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name

  # Engine
  engine         = var.engine
  engine_version = var.engine_version

  # Storage
  storage_type      = var.storage_type
  storage_encrypted = var.storage_encryption_enabled
  kms_key_id        = var.kms_key_id

  # Network
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = local.vpc_security_group_ids
  port                   = local.port
  network_type           = var.network_type
  availability_zones     = length(var.availability_zones) > 0 ? var.availability_zones : null

  # Authentication
  master_username                     = var.master_username
  master_password                     = var.master_user_password_management_enabled ? null : var.master_password
  manage_master_user_password         = var.master_user_password_management_enabled ? true : null
  master_user_secret_kms_key_id       = var.master_user_password_management_enabled ? var.master_user_secret_kms_key_id : null
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Database
  database_name = var.database_name

  # Parameter Group
  db_cluster_parameter_group_name = local.cluster_parameter_group_name

  # Backup
  backup_retention_period   = var.backup_retention_period
  preferred_backup_window   = var.preferred_backup_window
  copy_tags_to_snapshot     = var.snapshot_tag_copying_enabled
  skip_final_snapshot       = !var.final_snapshot_creation_enabled
  final_snapshot_identifier = local.final_snapshot_identifier
  snapshot_identifier       = var.snapshot_identifier
  backtrack_window          = local.is_mysql ? var.backtrack_window : 0

  # Maintenance
  preferred_maintenance_window = var.preferred_maintenance_window
  allow_major_version_upgrade  = var.major_version_upgrade_enabled
  apply_immediately            = var.immediate_apply_enabled
  deletion_protection          = var.deletion_protection_enabled

  # Monitoring
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Aurora features
  enable_http_endpoint           = var.http_endpoint_enabled
  enable_local_write_forwarding  = local.is_mysql ? var.local_write_forwarding_enabled : null
  enable_global_write_forwarding = local.is_postgres ? var.global_write_forwarding_enabled : null

  # Global database
  global_cluster_identifier = var.global_cluster_identifier
  source_region             = var.source_region

  # Serverless v2 scaling
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless_v2_scaling != null ? [var.serverless_v2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  # Point-in-time restore
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time != null ? [var.restore_to_point_in_time] : []
    content {
      source_cluster_identifier  = restore_to_point_in_time.value.source_cluster_identifier
      restore_type               = restore_to_point_in_time.value.restore_type
      use_latest_restorable_time = restore_to_point_in_time.value.use_latest_restorable_time
      restore_to_time            = restore_to_point_in_time.value.restore_to_time
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    ignore_changes = [
      snapshot_identifier,
      global_cluster_identifier,
    ]

    precondition {
      condition     = var.security_group_creation_enabled || var.security_group_id != null || length(var.security_group_ids) > 0
      error_message = "At least one security group must be provided: set security_group_creation_enabled = true, provide security_group_id, or provide security_group_ids."
    }

    precondition {
      condition     = var.master_user_password_management_enabled || var.master_password != null || try(data.aws_rds_cluster.password_preservation[0].arn != "", false) || var.snapshot_identifier != null || var.restore_to_point_in_time != null
      error_message = "A new cluster requires master credentials. Enable master_user_password_management_enabled, provide master_password, restore a cluster, or enable master_user_password_preservation_enabled when importing an existing cluster."
    }

    precondition {
      condition     = var.cluster_parameter_group_creation_enabled || var.cluster_parameter_group_name != null
      error_message = "cluster_parameter_group_name is required when cluster_parameter_group_creation_enabled is false."
    }

    precondition {
      condition     = var.db_parameter_group_creation_enabled || var.db_parameter_group_name != null
      error_message = "db_parameter_group_name is required when db_parameter_group_creation_enabled is false."
    }

    precondition {
      condition     = var.monitoring_interval == 0 || local.create_monitoring_role || var.monitoring_role_arn != null
      error_message = "monitoring_role_arn is required when monitoring_interval > 0 and monitoring_role_creation_enabled is false."
    }

    precondition {
      condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(local.valid_log_exports[var.engine], log)])
      error_message = "Invalid CloudWatch log export type for ${var.engine}. Valid types: ${join(", ", local.valid_log_exports[var.engine])}"
    }

    precondition {
      condition     = !var.local_write_forwarding_enabled || local.is_mysql
      error_message = "local_write_forwarding_enabled is only supported on Aurora MySQL."
    }

    precondition {
      condition     = !var.global_write_forwarding_enabled || local.is_postgres
      error_message = "global_write_forwarding_enabled is only supported on Aurora PostgreSQL."
    }

    precondition {
      condition     = var.backtrack_window == 0 || local.is_mysql
      error_message = "backtrack_window is only supported on Aurora MySQL."
    }

    precondition {
      condition     = !var.activity_stream_enabled || var.activity_stream_kms_key_id != null
      error_message = "activity_stream_kms_key_id is required when activity_stream_enabled is true."
    }

    precondition {
      condition     = !var.proxy_creation_enabled || var.master_user_password_management_enabled || length(var.proxy_auth_secret_arns) > 0
      error_message = "proxy_auth_secret_arns is required when proxy_creation_enabled is true and master_user_password_management_enabled is false."
    }

    precondition {
      condition     = !var.proxy_creation_enabled || length(var.subnet_ids) >= 2
      error_message = "At least 2 subnet_ids are required when proxy_creation_enabled is true."
    }
  }

  depends_on = [
    aws_rds_global_cluster.this,
  ]
}
