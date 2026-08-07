################################################################################
# RDS Primary Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier = var.name

  # Engine
  engine         = var.engine
  engine_version = local.engine_version
  license_model  = var.license_model

  # Instance
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput

  # Encryption
  storage_encrypted = var.storage_encryption_enabled
  kms_key_id        = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id]
  port                   = local.port
  publicly_accessible    = var.public_access_enabled
  availability_zone      = var.multi_az_enabled ? null : var.availability_zone
  ca_cert_identifier     = var.ca_cert_identifier

  # High Availability
  multi_az = var.multi_az_enabled

  # Authentication
  username                            = var.username
  password                            = var.master_user_password_management_enabled ? null : var.password
  manage_master_user_password         = var.master_user_password_management_enabled ? true : null
  master_user_secret_kms_key_id       = var.master_user_password_management_enabled ? var.master_user_secret_kms_key_id : null
  iam_database_authentication_enabled = local.iam_database_authentication_enabled

  # Database
  db_name              = local.db_name
  character_set_name   = var.character_set_name
  timezone             = var.timezone
  domain               = var.domain
  domain_iam_role_name = var.domain_iam_role_name

  # Parameter and Option Groups
  parameter_group_name = local.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name
  option_group_name    = local.create_option_group ? aws_db_option_group.this[0].name : var.option_group_name

  # Backup
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  copy_tags_to_snapshot     = var.snapshot_tag_copying_enabled
  delete_automated_backups  = var.automated_backups_deletion_enabled
  snapshot_identifier       = var.snapshot_identifier
  final_snapshot_identifier = local.final_snapshot_identifier
  skip_final_snapshot       = !var.final_snapshot_creation_enabled

  # Point-in-time recovery
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time != null ? [var.restore_to_point_in_time] : []
    content {
      restore_time                             = restore_to_point_in_time.value.restore_time
      source_db_instance_identifier            = restore_to_point_in_time.value.source_db_instance_identifier
      source_db_instance_automated_backups_arn = restore_to_point_in_time.value.source_db_instance_automated_backups_arn
      source_dbi_resource_id                   = restore_to_point_in_time.value.source_dbi_resource_id
      use_latest_restorable_time               = restore_to_point_in_time.value.use_latest_restorable_time
    }
  }

  # Maintenance
  maintenance_window          = var.maintenance_window
  auto_minor_version_upgrade  = var.minor_version_auto_upgrade_enabled
  allow_major_version_upgrade = var.major_version_upgrade_enabled
  apply_immediately           = var.immediate_apply_enabled
  deletion_protection         = var.deletion_protection_enabled

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? (local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null

  # Blue/Green Deployment
  dynamic "blue_green_update" {
    for_each = var.blue_green_update != null ? [var.blue_green_update] : []
    content {
      enabled = blue_green_update.value.enabled
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
      condition     = var.master_user_password_management_enabled || var.password != null || try(data.aws_db_instance.password_preservation[0].db_instance_arn != "", false) || var.snapshot_identifier != null || var.restore_to_point_in_time != null
      error_message = "A new database requires master credentials. Enable master_user_password_management_enabled, provide password, restore a database, or enable master_user_password_preservation_enabled when importing an existing database."
    }

    precondition {
      condition     = local.create_parameter_group || var.parameter_group_name != null
      error_message = "parameter_group_name is required when parameter_group_creation_enabled is false."
    }

    precondition {
      condition     = var.monitoring_interval == 0 || local.create_monitoring_role || var.monitoring_role_arn != null
      error_message = "monitoring_role_arn is required when monitoring_interval > 0 and monitoring_role_creation_enabled is false."
    }

    precondition {
      condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(local.valid_log_exports[local.engine_log_type], log)])
      error_message = "Invalid CloudWatch log export type for ${var.engine}. Valid types: ${join(", ", local.valid_log_exports[local.engine_log_type])}"
    }

    precondition {
      condition     = !var.proxy_creation_enabled || !local.is_oracle
      error_message = "RDS Proxy is not supported for Oracle engines."
    }

    precondition {
      condition     = !var.proxy_creation_enabled || var.master_user_password_management_enabled || length(var.proxy_auth_secret_arns) > 0
      error_message = "proxy_auth_secret_arns is required when proxy_creation_enabled is true and master_user_password_management_enabled is false."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]
}

################################################################################
# RDS Read Replicas
################################################################################

resource "aws_db_instance" "read_replica" {
  count = local.read_replica_count

  identifier = "${var.name}-replica-${count.index + 1}"

  # Replica source
  replicate_source_db = aws_db_instance.this.identifier

  # Instance (read replicas inherit engine from source)
  instance_class     = local.read_replica_instance_class
  storage_type       = var.storage_type
  iops               = var.iops
  storage_throughput = var.storage_throughput

  # Encryption (inherited from source, but can specify KMS key)
  kms_key_id = var.kms_key_id

  # Network
  vpc_security_group_ids = [local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id]
  port                   = local.port
  publicly_accessible    = var.public_access_enabled
  availability_zone      = length(var.read_replica_availability_zones) > count.index ? var.read_replica_availability_zones[count.index] : null
  ca_cert_identifier     = var.ca_cert_identifier

  # Multi-AZ not supported for read replicas in same region
  multi_az = false

  # Authentication (inherited from source)
  iam_database_authentication_enabled = local.iam_database_authentication_enabled

  # Parameter and Option Groups
  parameter_group_name = local.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name
  option_group_name    = local.create_option_group ? aws_db_option_group.this[0].name : var.option_group_name

  # Backup (read replicas have their own backup settings)
  backup_retention_period  = 0 # Disable automated backups for replicas by default
  copy_tags_to_snapshot    = var.snapshot_tag_copying_enabled
  delete_automated_backups = var.automated_backups_deletion_enabled
  skip_final_snapshot      = true # No final snapshot for replicas

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.minor_version_auto_upgrade_enabled
  apply_immediately          = var.immediate_apply_enabled
  deletion_protection        = false # Easier to manage replica lifecycle

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? (local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null

  # Blue/Green Deployment
  dynamic "blue_green_update" {
    for_each = var.blue_green_update != null ? [var.blue_green_update] : []
    content {
      enabled = blue_green_update.value.enabled
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-replica-${count.index + 1}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]
}
