################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 63
    error_message = "The name must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name))
    error_message = "The name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Engine
################################################################################

variable "engine" {
  type        = string
  description = "The database engine to use: mysql, postgres, mariadb, oracle-ee, oracle-se2, oracle-se2-cdb, sqlserver-ee, sqlserver-se, sqlserver-ex, sqlserver-web."

  validation {
    condition = contains([
      "mysql",
      "postgres",
      "mariadb",
      "oracle-ee",
      "oracle-se2",
      "oracle-se2-cdb",
      "sqlserver-ee",
      "sqlserver-se",
      "sqlserver-ex",
      "sqlserver-web"
    ], var.engine)
    error_message = "The engine must be one of: mysql, postgres, mariadb, oracle-ee, oracle-se2, oracle-se2-cdb, sqlserver-ee, sqlserver-se, sqlserver-ex, sqlserver-web."
  }
}

variable "engine_major_version" {
  type        = string
  description = "The major version of the database engine. If not specified, the latest available version will be used. Examples: 15 for PostgreSQL or SQL Server, 8.0 for MySQL, 19 for Oracle."
  default     = null
}

variable "engine_minor_version" {
  type        = string
  description = "The optional minor version of the database engine. Appended to engine_major_version when specified. Examples: 4, 35, 0.0.ru-2023-10.rur-2023-10.r1."
  default     = null

  validation {
    condition     = var.engine_minor_version == null || var.engine_major_version != null
    error_message = "The engine_major_version must be set when engine_minor_version is set."
  }
}

variable "license_model" {
  type        = string
  description = "The license model for the DB instance. Required for Oracle and SQL Server. Valid values: license-included, bring-your-own-license, general-public-license."
  default     = null

  validation {
    condition     = var.license_model == null || contains(["license-included", "bring-your-own-license", "general-public-license"], var.license_model)
    error_message = "The license_model must be one of: license-included, bring-your-own-license, general-public-license."
  }
}

################################################################################
# Instance
################################################################################

variable "instance_class" {
  type        = string
  description = "The compute and memory capacity of the DB instance (e.g., db.t3.micro, db.r6g.large)."

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "The instance_class must be a valid RDS instance type starting with 'db.'."
  }
}

variable "allocated_storage" {
  type        = number
  description = "The allocated storage in gibibytes (GiB)."

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "The allocated_storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  type        = number
  description = "The upper limit to which RDS can automatically scale the storage. Set to 0 to disable storage autoscaling."
  default     = 0

  validation {
    condition     = var.max_allocated_storage >= 0 && var.max_allocated_storage <= 65536
    error_message = "The max_allocated_storage must be between 0 and 65536 GiB."
  }
}

variable "storage_type" {
  type        = string
  description = "The storage type: gp2, gp3, io1, io2, or standard."
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.storage_type)
    error_message = "The storage_type must be one of: gp2, gp3, io1, io2, standard."
  }
}

variable "iops" {
  type        = number
  description = "The amount of provisioned IOPS. Required for io1 and io2 storage types, optional for gp3."
  default     = null

  validation {
    condition     = var.iops == null || (var.iops >= 1000 && var.iops <= 256000)
    error_message = "The iops must be between 1000 and 256000."
  }
}

variable "storage_throughput" {
  type        = number
  description = "The storage throughput in MiB/s. Only valid for gp3 storage type."
  default     = null

  validation {
    condition     = var.storage_throughput == null || (var.storage_throughput >= 125 && var.storage_throughput <= 1000)
    error_message = "The storage_throughput must be between 125 and 1000 MiB/s."
  }
}

################################################################################
# Encryption
################################################################################

variable "storage_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest for the DB instance."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "The ARN of the KMS key for storage encryption. If not specified, the default AWS managed key is used."
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws(-[a-z]+)?:kms:", var.kms_key_id))
    error_message = "The kms_key_id must be a valid KMS key ARN."
  }
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the RDS instance will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the DB subnet group. At least two subnets in different AZs are required."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs in different availability zones are required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "port" {
  type        = number
  description = "The port on which the DB accepts connections. If not specified, defaults based on engine (3306 for MySQL/MariaDB, 5432 for PostgreSQL, 1521 for Oracle, 1433 for SQL Server)."
  default     = null

  validation {
    condition     = var.port == null || (var.port >= 1 && var.port <= 65535)
    error_message = "The port must be between 1 and 65535."
  }
}

variable "public_access_enabled" {
  type        = bool
  description = "Whether the DB instance is publicly accessible. Should be false for production workloads."
  default     = false
}

variable "availability_zone" {
  type        = string
  description = "The AZ for the DB instance. If multi_az_enabled is true, this is ignored."
  default     = null
}

variable "ca_cert_identifier" {
  type        = string
  description = "The identifier of the CA certificate for the DB instance."
  default     = null
}

################################################################################
# Security Group
################################################################################

variable "security_group_creation_enabled" {
  type        = bool
  description = "Whether to create a security group for the RDS instance."
  default     = true
}

variable "security_group_id" {
  type        = string
  description = "The ID of an existing security group to use. Required if security_group_creation_enabled is false."
  default     = null

  validation {
    condition     = var.security_group_id == null || can(regex("^sg-", var.security_group_id))
    error_message = "The security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs allowed to access the RDS instance."
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All allowed_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "A list of CIDR blocks allowed to access the RDS instance."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_cidr_blocks must be valid CIDR blocks."
  }
}

################################################################################
# High Availability
################################################################################

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ deployment for high availability."
  default     = false
}

variable "read_replica_creation_enabled" {
  type        = bool
  description = "Whether to create read replicas for the primary instance."
  default     = false
}

variable "read_replica_count" {
  type        = number
  description = "The number of read replicas to create."
  default     = 1

  validation {
    condition     = var.read_replica_count >= 0 && var.read_replica_count <= 15
    error_message = "The read_replica_count must be between 0 and 15."
  }
}

variable "read_replica_instance_class" {
  type        = string
  description = "The instance class for read replicas. If not specified, uses the same as the primary instance."
  default     = null

  validation {
    condition     = var.read_replica_instance_class == null || can(regex("^db\\.", var.read_replica_instance_class))
    error_message = "The read_replica_instance_class must be a valid RDS instance type starting with 'db.'."
  }
}

variable "read_replica_availability_zones" {
  type        = list(string)
  description = "A list of availability zones for read replicas. If not specified, AWS chooses automatically."
  default     = []
}

################################################################################
# Authentication
################################################################################

variable "username" {
  type        = string
  description = "The master username for the database."

  validation {
    condition     = length(var.username) >= 1 && length(var.username) <= 63
    error_message = "The username must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.username))
    error_message = "The username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "password" {
  type        = string
  description = "Optional master password for the database when Secrets Manager password management is disabled. Leave null when importing or restoring a database whose existing password must remain unmanaged by Terraform."
  default     = null
  sensitive   = true

  validation {
    condition     = var.password == null || (length(var.password) >= 8 && length(var.password) <= 128)
    error_message = "The password must be between 8 and 128 characters."
  }
}

variable "master_user_password_management_enabled" {
  type        = bool
  description = "Whether AWS RDS manages the master user password with Secrets Manager. Disable this before importing a database whose existing password is managed externally."
  default     = true
}

variable "master_user_password_preservation_enabled" {
  type        = bool
  description = "Whether to preserve an existing externally managed master password by omitting password configuration. The named database must already exist in AWS, and master user password management must be disabled."
  default     = false

  validation {
    condition     = !var.master_user_password_preservation_enabled || !var.master_user_password_management_enabled
    error_message = "master_user_password_preservation_enabled and master_user_password_management_enabled cannot both be true."
  }
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "The ARN of the KMS key to encrypt the master user password secret in Secrets Manager."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^arn:aws(-[a-z]+)?:kms:", var.master_user_secret_kms_key_id))
    error_message = "The master_user_secret_kms_key_id must be a valid KMS key ARN."
  }
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Enable IAM database authentication. Supported for MySQL and PostgreSQL."
  default     = false
}

################################################################################
# Database
################################################################################

variable "db_name" {
  type        = string
  description = "The name of the database to create. If not specified, no database is created."
  default     = null

  validation {
    condition     = var.db_name == null || (length(var.db_name) >= 1 && length(var.db_name) <= 64)
    error_message = "The db_name must be between 1 and 64 characters."
  }

  validation {
    condition     = var.db_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "The db_name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "character_set_name" {
  type        = string
  description = "The character set name for Oracle or SQL Server databases."
  default     = null
}

variable "timezone" {
  type        = string
  description = "The timezone for SQL Server databases."
  default     = null
}

variable "domain" {
  type        = string
  description = "The Active Directory directory ID for SQL Server."
  default     = null
}

variable "domain_iam_role_name" {
  type        = string
  description = "The name of the IAM role for Active Directory integration."
  default     = null
}

################################################################################
# Backup
################################################################################

variable "backup_retention_period" {
  type        = number
  description = "The number of days to retain automated backups. Set to 0 to disable."
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "The backup_retention_period must be between 0 and 35."
  }
}

variable "backup_window" {
  type        = string
  description = "The daily time range during which automated backups are created (e.g., 03:00-04:00 UTC)."
  default     = null

  validation {
    condition     = var.backup_window == null || can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]-([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "The backup_window must be in the format HH:MM-HH:MM (e.g., 03:00-04:00)."
  }
}

variable "snapshot_tag_copying_enabled" {
  type        = bool
  description = "Whether to copy tags to snapshots."
  default     = true
}

variable "automated_backups_deletion_enabled" {
  type        = bool
  description = "Whether to delete automated backups when the DB instance is deleted."
  default     = true
}

variable "snapshot_identifier" {
  type        = string
  description = "The snapshot ID to restore from when creating the DB instance."
  default     = null
}

variable "final_snapshot_identifier" {
  type        = string
  description = "The name of the final snapshot when deleting the DB instance. Required if final_snapshot_creation_enabled is true."
  default     = null

  validation {
    condition     = var.final_snapshot_identifier == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.final_snapshot_identifier))
    error_message = "The final_snapshot_identifier must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "final_snapshot_creation_enabled" {
  type        = bool
  description = "Whether to create a final snapshot when deleting the DB instance."
  default     = true
}

variable "restore_to_point_in_time" {
  type = object({
    restore_time                             = optional(string)
    source_db_instance_identifier            = optional(string)
    source_db_instance_automated_backups_arn = optional(string)
    source_dbi_resource_id                   = optional(string)
    use_latest_restorable_time               = optional(bool)
  })
  description = "Configuration for point-in-time recovery."
  default     = null
}

################################################################################
# Maintenance
################################################################################

variable "maintenance_window" {
  type        = string
  description = "The weekly time range for maintenance (e.g., sun:03:00-sun:04:00 UTC)."
  default     = null

  validation {
    condition     = var.maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "The maintenance_window must be in the format ddd:HH:MM-ddd:HH:MM (e.g., sun:03:00-sun:04:00)."
  }
}

variable "minor_version_auto_upgrade_enabled" {
  type        = bool
  description = "Enable automatic minor version upgrades during the maintenance window."
  default     = true
}

variable "major_version_upgrade_enabled" {
  type        = bool
  description = "Allow major version upgrades when changing engine versions."
  default     = false
}

variable "immediate_apply_enabled" {
  type        = bool
  description = "Whether to apply changes immediately or during the next maintenance window."
  default     = false
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "Enable deletion protection for the DB instance."
  default     = true
}

################################################################################
# Monitoring
################################################################################

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "A list of log types to export to CloudWatch Logs. Valid values depend on the engine."
  default     = []
}

variable "monitoring_interval" {
  type        = number
  description = "The interval in seconds for Enhanced Monitoring metrics. Valid values: 0, 1, 5, 10, 15, 30, 60."
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "The monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "monitoring_role_arn" {
  type        = string
  description = "The ARN of the IAM role for Enhanced Monitoring. Required if monitoring_interval > 0 and monitoring_role_creation_enabled is false."
  default     = null

  validation {
    condition     = var.monitoring_role_arn == null || can(regex("^arn:aws(-[a-z]+)?:iam::", var.monitoring_role_arn))
    error_message = "The monitoring_role_arn must be a valid IAM role ARN."
  }
}

variable "monitoring_role_creation_enabled" {
  type        = bool
  description = "Whether to create an IAM role for Enhanced Monitoring."
  default     = true
}

variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights for the DB instance."
  default     = true
}

variable "performance_insights_retention_period" {
  type        = number
  description = "The retention period for Performance Insights data in days. Valid values: 7, 31-731."
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731)
    error_message = "The performance_insights_retention_period must be 7 or between 31 and 731."
  }
}

variable "performance_insights_kms_key_id" {
  type        = string
  description = "The ARN of the KMS key for Performance Insights encryption."
  default     = null

  validation {
    condition     = var.performance_insights_kms_key_id == null || can(regex("^arn:aws(-[a-z]+)?:kms:", var.performance_insights_kms_key_id))
    error_message = "The performance_insights_kms_key_id must be a valid KMS key ARN."
  }
}

################################################################################
# CloudWatch Alarms
################################################################################

variable "cloudwatch_alarms_creation_enabled" {
  type        = bool
  description = "Create CloudWatch alarms for CPU, storage, and connections."
  default     = false
}

variable "cloudwatch_alarm_cpu_threshold" {
  type        = number
  description = "The CPU utilization threshold (percent) for the CloudWatch alarm."
  default     = 80

  validation {
    condition     = var.cloudwatch_alarm_cpu_threshold >= 0 && var.cloudwatch_alarm_cpu_threshold <= 100
    error_message = "The cloudwatch_alarm_cpu_threshold must be between 0 and 100."
  }
}

variable "cloudwatch_alarm_storage_threshold" {
  type        = number
  description = "The free storage space threshold (bytes) for the CloudWatch alarm."
  default     = 5368709120 # 5 GiB

  validation {
    condition     = var.cloudwatch_alarm_storage_threshold >= 0
    error_message = "The cloudwatch_alarm_storage_threshold must be at least 0."
  }
}

variable "cloudwatch_alarm_connections_threshold" {
  type        = number
  description = "The database connections threshold for the CloudWatch alarm."
  default     = 100

  validation {
    condition     = var.cloudwatch_alarm_connections_threshold >= 1
    error_message = "The cloudwatch_alarm_connections_threshold must be at least 1."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  type        = number
  description = "The number of periods over which data is compared to the threshold."
  default     = 2

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "The cloudwatch_alarm_evaluation_periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period" {
  type        = number
  description = "The period in seconds over which the statistic is applied."
  default     = 300

  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600], var.cloudwatch_alarm_period)
    error_message = "The cloudwatch_alarm_period must be one of: 10, 30, 60, 300, 900, or 3600 seconds."
  }
}

variable "cloudwatch_alarm_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when the CloudWatch alarm transitions to ALARM state."
  default     = []
}

variable "cloudwatch_ok_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when the CloudWatch alarm transitions to OK state."
  default     = []
}

################################################################################
# Parameter Group
################################################################################

variable "parameter_group_creation_enabled" {
  type        = bool
  description = "Whether to create a DB parameter group."
  default     = true
}

variable "parameter_group_name" {
  type        = string
  description = "The name of an existing DB parameter group to use. Required if parameter_group_creation_enabled is false."
  default     = null
}

variable "parameter_group_family" {
  type        = string
  description = "The family of the DB parameter group (e.g., mysql8.0, postgres15). If not specified, it is derived from the engine and version."
  default     = null
}

variable "parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  description = "A list of parameter name/value pairs to apply to the parameter group."
  default     = []

  validation {
    condition     = alltrue([for p in var.parameters : contains(["immediate", "pending-reboot"], p.apply_method)])
    error_message = "The apply_method must be 'immediate' or 'pending-reboot'."
  }
}

################################################################################
# Option Group
################################################################################

variable "option_group_creation_enabled" {
  type        = bool
  description = "Whether to create a DB option group. Typically used for Oracle and SQL Server."
  default     = false
}

variable "option_group_name" {
  type        = string
  description = "The name of an existing DB option group to use."
  default     = null
}

variable "option_group_engine_version" {
  type        = string
  description = "The major engine version for the option group. If not specified, it is derived from engine_major_version."
  default     = null
}

variable "options" {
  type = list(object({
    option_name                    = string
    port                           = optional(number)
    version                        = optional(string)
    db_security_group_memberships  = optional(list(string))
    vpc_security_group_memberships = optional(list(string))
    option_settings = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
  description = "A list of options to apply to the option group."
  default     = []
}

################################################################################
# Blue/Green Deployment
################################################################################

variable "blue_green_update" {
  type = object({
    enabled = bool
  })
  description = "Configuration for Blue/Green deployments."
  default     = null
}

################################################################################
# RDS Proxy
################################################################################

variable "proxy_creation_enabled" {
  type        = bool
  description = "Whether to create an RDS Proxy in front of the database. Requires master_user_password_management_enabled or proxy_auth_secret_arns."
  default     = false
}

variable "proxy_auth_secret_arns" {
  type        = list(string)
  description = "List of Secrets Manager secret ARNs containing database credentials for the proxy. Defaults to the managed master user secret when master_user_password_management_enabled is true."
  default     = []

  validation {
    condition     = alltrue([for arn in var.proxy_auth_secret_arns : startswith(arn, "arn:")])
    error_message = "All proxy_auth_secret_arns must be valid Secrets Manager secret ARNs."
  }
}

variable "proxy_secret_kms_key_arns" {
  type        = list(string)
  description = "List of KMS key ARNs used to encrypt the proxy auth secrets when using customer-managed keys. The master user secret KMS key is included automatically."
  default     = []

  validation {
    condition     = alltrue([for arn in var.proxy_secret_kms_key_arns : startswith(arn, "arn:")])
    error_message = "All proxy_secret_kms_key_arns must be valid KMS key ARNs."
  }
}

variable "proxy_iam_auth_enabled" {
  type        = bool
  description = "Whether clients must use IAM authentication to connect to the proxy."
  default     = false
}

variable "proxy_tls_requirement_enabled" {
  type        = bool
  description = "Whether Transport Layer Security (TLS) encryption is required for connections to the proxy."
  default     = true
}

variable "proxy_debug_logging_enabled" {
  type        = bool
  description = "Whether the proxy logs detailed connection information, including SQL statements, to CloudWatch Logs."
  default     = false
}

variable "proxy_idle_client_timeout" {
  type        = number
  description = "The number of seconds a client connection to the proxy can be idle before the proxy disconnects it."
  default     = 1800

  validation {
    condition     = var.proxy_idle_client_timeout >= 1 && var.proxy_idle_client_timeout <= 28800
    error_message = "The proxy_idle_client_timeout must be between 1 and 28800 seconds."
  }
}

variable "proxy_connection_borrow_timeout" {
  type        = number
  description = "The number of seconds the proxy waits for a connection to become available in the connection pool before returning a timeout error."
  default     = 120

  validation {
    condition     = var.proxy_connection_borrow_timeout >= 0
    error_message = "The proxy_connection_borrow_timeout must be greater than or equal to 0."
  }
}

variable "proxy_init_query" {
  type        = string
  description = "One or more SQL statements for the proxy to run when opening each new database connection."
  default     = null
}

variable "proxy_max_connections_percent" {
  type        = number
  description = "The maximum size of the proxy connection pool as a percentage of the max_connections setting of the target database."
  default     = 100

  validation {
    condition     = var.proxy_max_connections_percent >= 1 && var.proxy_max_connections_percent <= 100
    error_message = "The proxy_max_connections_percent must be between 1 and 100."
  }
}

variable "proxy_max_idle_connections_percent" {
  type        = number
  description = "The maximum percentage of idle database connections the proxy keeps open, as a percentage of the max_connections setting of the target database."
  default     = 50

  validation {
    condition     = var.proxy_max_idle_connections_percent >= 0 && var.proxy_max_idle_connections_percent <= 100
    error_message = "The proxy_max_idle_connections_percent must be between 0 and 100."
  }
}

variable "proxy_session_pinning_filters" {
  type        = list(string)
  description = "Session pinning filters for the proxy. Valid value: EXCLUDE_VARIABLE_SETS."
  default     = []

  validation {
    condition     = alltrue([for f in var.proxy_session_pinning_filters : f == "EXCLUDE_VARIABLE_SETS"])
    error_message = "The only valid session pinning filter is EXCLUDE_VARIABLE_SETS."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
