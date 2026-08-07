################################################################################
# General
################################################################################

variable "name" {
  description = "Name of the Aurora cluster. Used as a prefix for all resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name)) && length(var.name) >= 1 && length(var.name) <= 63
    error_message = "Name must be 1-63 characters, start with a letter, and contain only alphanumeric characters and hyphens."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

################################################################################
# Engine
################################################################################

variable "engine" {
  description = "The Aurora database engine type. Valid values: aurora-mysql, aurora-postgresql."
  type        = string

  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.engine)
    error_message = "Engine must be one of: aurora-mysql, aurora-postgresql."
  }
}

variable "engine_version" {
  description = "The Aurora engine version. If not specified, the default engine version will be used."
  type        = string
  default     = null
}

################################################################################
# Cluster
################################################################################

variable "database_name" {
  description = "Name for an automatically created database on cluster creation. Must be 1-64 characters if set."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || (length(var.database_name) >= 1 && length(var.database_name) <= 64)
    error_message = "Database name must be 1-64 characters if set."
  }
}

variable "port" {
  description = "The port on which the DB accepts connections. Defaults to 3306 for MySQL, 5432 for PostgreSQL."
  type        = number
  default     = null

  validation {
    condition     = var.port == null || (var.port >= 1 && var.port <= 65535)
    error_message = "Port must be between 1 and 65535."
  }
}

variable "storage_type" {
  description = "Storage type for the Aurora cluster. Valid values: aurora (standard), aurora-iopt1 (I/O-Optimized)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "Storage type must be one of: aurora, aurora-iopt1."
  }
}

variable "network_type" {
  description = "The network type of the cluster. Valid values: IPV4, DUAL."
  type        = string
  default     = "IPV4"

  validation {
    condition     = contains(["IPV4", "DUAL"], var.network_type)
    error_message = "Network type must be one of: IPV4, DUAL."
  }
}

variable "http_endpoint_enabled" {
  description = "Enable HTTP endpoint (Data API) for the Aurora cluster."
  type        = bool
  default     = false
}

variable "local_write_forwarding_enabled" {
  description = "Enable local write forwarding for the Aurora cluster. Only supported on Aurora MySQL."
  type        = bool
  default     = false
}

variable "ca_certificate_identifier" {
  description = "The identifier of the CA certificate for the DB instances."
  type        = string
  default     = null
}

variable "immediate_apply_enabled" {
  description = "Specifies whether any cluster modifications are applied immediately, or during the next maintenance window."
  type        = bool
  default     = false
}

variable "deletion_protection_enabled" {
  description = "If the cluster should have deletion protection enabled."
  type        = bool
  default     = true
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  description = "The VPC ID where the Aurora cluster will be created."
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-'."
  }
}

variable "subnet_ids" {
  description = "A list of VPC subnet IDs for the DB subnet group. Must contain at least 2 subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet IDs must start with 'subnet-'."
  }
}

variable "availability_zones" {
  description = "List of EC2 Availability Zones for the DB cluster."
  type        = list(string)
  default     = []
}

variable "public_access_enabled" {
  description = "Bool to control if instances are publicly accessible. Default is false."
  type        = bool
  default     = false
}

variable "db_subnet_group_name" {
  description = "The name of an existing DB subnet group to use. If not provided, a new one will be created."
  type        = string
  default     = null
}

################################################################################
# Security Group
################################################################################

variable "security_group_creation_enabled" {
  description = "Whether to create a new security group for the Aurora cluster."
  type        = bool
  default     = true
}

variable "security_group_id" {
  description = "An existing security group ID to use for the Aurora cluster."
  type        = string
  default     = null

  validation {
    condition     = var.security_group_id == null || can(regex("^sg-", var.security_group_id))
    error_message = "Security group ID must start with 'sg-'."
  }
}

variable "security_group_ids" {
  description = "List of additional security group IDs to attach to the Aurora cluster."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security group IDs must start with 'sg-'."
  }
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access the Aurora cluster."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security group IDs must start with 'sg-'."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the Aurora cluster."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All values must be valid CIDR blocks."
  }
}

################################################################################
# Authentication
################################################################################

variable "master_username" {
  description = "Username for the master DB user. Must start with a letter and be 1-63 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.master_username)) && length(var.master_username) >= 1 && length(var.master_username) <= 63
    error_message = "Master username must be 1-63 characters, start with a letter, and contain only alphanumeric characters and underscores."
  }
}

variable "master_password" {
  description = "Optional password for the master DB user when Secrets Manager password management is disabled. Leave null when importing or restoring a cluster whose existing password must remain unmanaged by Terraform."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.master_password == null || (length(var.master_password) >= 8 && length(var.master_password) <= 128)
    error_message = "Master password must be 8-128 characters if set."
  }
}

variable "master_user_password_management_enabled" {
  description = "Whether Amazon Aurora manages the master user password with Secrets Manager. Disable this before importing a cluster whose existing password is managed externally."
  type        = bool
  default     = true
}

variable "master_user_password_preservation_enabled" {
  description = "Whether to preserve an existing externally managed master password by omitting password configuration. The named cluster must already exist in AWS, and master user password management must be disabled."
  type        = bool
  default     = false

  validation {
    condition     = !var.master_user_password_preservation_enabled || !var.master_user_password_management_enabled
    error_message = "master_user_password_preservation_enabled and master_user_password_management_enabled cannot both be true."
  }
}

variable "master_user_secret_kms_key_id" {
  description = "The ARN of the KMS key used to encrypt the master user secret in Secrets Manager."
  type        = string
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^arn:aws:kms:", var.master_user_secret_kms_key_id))
    error_message = "KMS key ID must be an ARN starting with 'arn:aws:kms:'."
  }
}

variable "iam_database_authentication_enabled" {
  description = "Specifies whether IAM database authentication is enabled."
  type        = bool
  default     = false
}

################################################################################
# Encryption
################################################################################

variable "storage_encryption_enabled" {
  description = "Specifies whether the DB cluster storage is encrypted."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "The ARN of the KMS key to use for encryption at rest."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws:kms:", var.kms_key_id))
    error_message = "KMS key ID must be an ARN starting with 'arn:aws:kms:'."
  }
}

################################################################################
# Instances
################################################################################

variable "instance_class" {
  description = "The instance class for Aurora instances. Must start with 'db.'. Ignored when serverless_v2_scaling is set."
  type        = string

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "Instance class must start with 'db.'."
  }
}

variable "reader_count" {
  description = "Number of reader instances to create. Valid range: 0-15."
  type        = number
  default     = 1

  validation {
    condition     = var.reader_count >= 0 && var.reader_count <= 15
    error_message = "Reader count must be between 0 and 15."
  }
}

variable "reader_instance_class" {
  description = "The instance class for reader instances. Defaults to instance_class if not set."
  type        = string
  default     = null

  validation {
    condition     = var.reader_instance_class == null || can(regex("^db\\.", var.reader_instance_class))
    error_message = "Reader instance class must start with 'db.'."
  }
}

variable "instances" {
  description = "Map of instance configurations for full per-instance control. Overrides reader_count when provided."
  type = map(object({
    instance_class               = optional(string)
    availability_zone            = optional(string)
    public_access_enabled        = optional(bool)
    promotion_tier               = optional(number)
    performance_insights_enabled = optional(bool)
    monitoring_interval          = optional(number)
    tags                         = optional(map(string))
  }))
  default = {}
}

variable "serverless_v2_scaling" {
  description = "Serverless v2 scaling configuration. When set, instances default to db.serverless class."
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = null

  validation {
    condition     = var.serverless_v2_scaling == null || (var.serverless_v2_scaling.min_capacity >= 0.5 && var.serverless_v2_scaling.min_capacity <= 256)
    error_message = "Serverless v2 min_capacity must be between 0.5 and 256 ACUs."
  }

  validation {
    condition     = var.serverless_v2_scaling == null || (var.serverless_v2_scaling.max_capacity >= 0.5 && var.serverless_v2_scaling.max_capacity <= 256)
    error_message = "Serverless v2 max_capacity must be between 0.5 and 256 ACUs."
  }
}

variable "promotion_tier" {
  description = "Default failover priority for instances. Valid range: 0-15. Lower values have higher priority."
  type        = number
  default     = null

  validation {
    condition     = var.promotion_tier == null || (var.promotion_tier >= 0 && var.promotion_tier <= 15)
    error_message = "Promotion tier must be between 0 and 15."
  }
}

################################################################################
# Backup and Restore
################################################################################

variable "backup_retention_period" {
  description = "The number of days to retain backups. Aurora minimum is 1."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "The daily time range during which automated backups are created (HH:MM-HH:MM in UTC)."
  type        = string
  default     = null

  validation {
    condition     = var.preferred_backup_window == null || can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.preferred_backup_window))
    error_message = "Backup window must be in HH:MM-HH:MM format."
  }
}

variable "snapshot_tag_copying_enabled" {
  description = "Copy all cluster tags to snapshots."
  type        = bool
  default     = true
}

variable "final_snapshot_creation_enabled" {
  description = "Determines whether a final DB snapshot is created before the cluster is deleted."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "The name of the final snapshot when the cluster is deleted. Auto-generated if not provided."
  type        = string
  default     = null
}

variable "snapshot_identifier" {
  description = "Specifies a snapshot to create the cluster from."
  type        = string
  default     = null
}

variable "restore_to_point_in_time" {
  description = "Configuration for restoring the cluster to a point in time."
  type = object({
    source_cluster_identifier  = string
    restore_type               = optional(string, "full-copy")
    use_latest_restorable_time = optional(bool, true)
    restore_to_time            = optional(string)
  })
  default = null
}

variable "backtrack_window" {
  description = "The target backtrack window, in seconds. Only supported for Aurora MySQL. Valid range: 0-259200 (72 hours)."
  type        = number
  default     = 0

  validation {
    condition     = var.backtrack_window >= 0 && var.backtrack_window <= 259200
    error_message = "Backtrack window must be between 0 and 259200 seconds (72 hours)."
  }
}

variable "preferred_maintenance_window" {
  description = "The weekly time range during which system maintenance can occur (ddd:HH:MM-ddd:HH:MM in UTC)."
  type        = string
  default     = null

  validation {
    condition     = var.preferred_maintenance_window == null || can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.preferred_maintenance_window))
    error_message = "Maintenance window must be in ddd:HH:MM-ddd:HH:MM format."
  }
}

variable "major_version_upgrade_enabled" {
  description = "Enable to allow major engine version upgrades when changing engine versions."
  type        = bool
  default     = false
}

variable "minor_version_auto_upgrade_enabled" {
  description = "Indicates that minor engine upgrades will be applied automatically during the maintenance window."
  type        = bool
  default     = true
}

################################################################################
# Parameter Groups
################################################################################

variable "cluster_parameter_group_creation_enabled" {
  description = "Whether to create a new cluster parameter group."
  type        = bool
  default     = true
}

variable "cluster_parameter_group_name" {
  description = "The name of an existing cluster parameter group to use. Required if cluster_parameter_group_creation_enabled is false."
  type        = string
  default     = null
}

variable "cluster_parameter_group_family" {
  description = "The family of the cluster parameter group. Auto-derived from engine and version if not provided."
  type        = string
  default     = null
}

variable "cluster_parameters" {
  description = "A list of cluster parameter objects to apply."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "db_parameter_group_creation_enabled" {
  description = "Whether to create a new DB parameter group for instances."
  type        = bool
  default     = true
}

variable "db_parameter_group_name" {
  description = "The name of an existing DB parameter group to use. Required if db_parameter_group_creation_enabled is false."
  type        = string
  default     = null
}

variable "db_parameter_group_family" {
  description = "The family of the DB parameter group. Auto-derived from engine and version if not provided."
  type        = string
  default     = null
}

variable "db_parameters" {
  description = "A list of DB parameter objects to apply."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

################################################################################
# Monitoring
################################################################################

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch. Valid values depend on engine: aurora-mysql (audit, error, general, slowquery), aurora-postgresql (postgresql)."
  type        = list(string)
  default     = []
}

variable "monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected. Valid values: 0, 1, 5, 10, 15, 30, 60."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "monitoring_role_arn" {
  description = "The ARN of the IAM role for Enhanced Monitoring. If not provided and monitoring_role_creation_enabled is true, a new role will be created."
  type        = string
  default     = null

  validation {
    condition     = var.monitoring_role_arn == null || can(regex("^arn:aws:iam:", var.monitoring_role_arn))
    error_message = "Monitoring role ARN must start with 'arn:aws:iam:'."
  }
}

variable "monitoring_role_creation_enabled" {
  description = "Whether to create an IAM role for Enhanced Monitoring."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights is enabled."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data. Valid values: 7, or 31-731."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731)
    error_message = "Performance Insights retention period must be 7, or between 31 and 731 days."
  }
}

variable "performance_insights_kms_key_id" {
  description = "The ARN of the KMS key to encrypt Performance Insights data."
  type        = string
  default     = null

  validation {
    condition     = var.performance_insights_kms_key_id == null || can(regex("^arn:aws:kms:", var.performance_insights_kms_key_id))
    error_message = "Performance Insights KMS key must be an ARN starting with 'arn:aws:kms:'."
  }
}

variable "cloudwatch_alarms_creation_enabled" {
  description = "Whether to create CloudWatch alarms for the Aurora cluster."
  type        = bool
  default     = false
}

variable "cloudwatch_alarm_cpu_threshold" {
  description = "The CPU utilization threshold for the CloudWatch alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.cloudwatch_alarm_cpu_threshold >= 0 && var.cloudwatch_alarm_cpu_threshold <= 100
    error_message = "CPU alarm threshold must be between 0 and 100."
  }
}

variable "cloudwatch_alarm_memory_threshold" {
  description = "The freeable memory threshold in bytes for the CloudWatch alarm."
  type        = number
  default     = 268435456 # 256 MiB

  validation {
    condition     = var.cloudwatch_alarm_memory_threshold > 0
    error_message = "Memory alarm threshold must be greater than 0."
  }
}

variable "cloudwatch_alarm_connections_threshold" {
  description = "The database connections threshold for the CloudWatch alarm."
  type        = number
  default     = 100

  validation {
    condition     = var.cloudwatch_alarm_connections_threshold >= 1
    error_message = "Connections alarm threshold must be at least 1."
  }
}

variable "cloudwatch_alarm_actions" {
  description = "List of ARNs to notify when the alarm transitions to ALARM state."
  type        = list(string)
  default     = []
}

variable "cloudwatch_ok_actions" {
  description = "List of ARNs to notify when the alarm transitions to OK state."
  type        = list(string)
  default     = []
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "The number of periods over which data is compared to the threshold."
  type        = number
  default     = 2

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "Evaluation periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period" {
  description = "The period in seconds over which the statistic is applied."
  type        = number
  default     = 300

  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600], var.cloudwatch_alarm_period)
    error_message = "Alarm period must be one of: 10, 30, 60, 300, 900, 3600."
  }
}

################################################################################
# Auto-scaling
################################################################################

variable "autoscaling_enabled" {
  description = "Whether to enable Application Auto Scaling for Aurora read replicas."
  type        = bool
  default     = false
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of read replicas when auto-scaling."
  type        = number
  default     = 1

  validation {
    condition     = var.autoscaling_min_capacity >= 0
    error_message = "Auto-scaling minimum capacity must be >= 0."
  }
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of read replicas when auto-scaling."
  type        = number
  default     = 3

  validation {
    condition     = var.autoscaling_max_capacity >= 1
    error_message = "Auto-scaling maximum capacity must be >= 1."
  }
}

variable "autoscaling_target_cpu" {
  description = "The target CPU utilization percentage for auto-scaling."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscaling_target_cpu >= 1 && var.autoscaling_target_cpu <= 100
    error_message = "Auto-scaling target CPU must be between 1 and 100."
  }
}

variable "autoscaling_target_connections" {
  description = "The target number of connections for auto-scaling. If set, a connection-based scaling policy is created."
  type        = number
  default     = null

  validation {
    condition     = var.autoscaling_target_connections == null || var.autoscaling_target_connections >= 1
    error_message = "Auto-scaling target connections must be >= 1."
  }
}

variable "autoscaling_scale_in_cooldown" {
  description = "The cooldown period (in seconds) before a scale-in activity takes effect."
  type        = number
  default     = 300

  validation {
    condition     = var.autoscaling_scale_in_cooldown >= 0
    error_message = "Scale-in cooldown must be >= 0."
  }
}

variable "autoscaling_scale_out_cooldown" {
  description = "The cooldown period (in seconds) before a scale-out activity takes effect."
  type        = number
  default     = 300

  validation {
    condition     = var.autoscaling_scale_out_cooldown >= 0
    error_message = "Scale-out cooldown must be >= 0."
  }
}

variable "autoscaling_policy_name" {
  description = "The name of the auto-scaling policy. Auto-generated if not provided."
  type        = string
  default     = null
}

################################################################################
# Custom Endpoints
################################################################################

variable "custom_endpoints" {
  description = "Map of custom endpoint configurations. Each endpoint can be of type READER or ANY."
  type = map(object({
    type             = string
    static_members   = optional(list(string))
    excluded_members = optional(list(string))
    tags             = optional(map(string))
  }))
  default = {}
}

################################################################################
# Global Database
################################################################################

variable "global_cluster_creation_enabled" {
  description = "Whether to create a global Aurora cluster."
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "The global cluster identifier. Used to join an existing global cluster or create a new one."
  type        = string
  default     = null

  validation {
    condition     = var.global_cluster_identifier == null || (length(var.global_cluster_identifier) >= 1 && length(var.global_cluster_identifier) <= 63)
    error_message = "Global cluster identifier must be 1-63 characters."
  }
}

variable "source_region" {
  description = "The source region for cross-region replication in a global database."
  type        = string
  default     = null
}

variable "global_write_forwarding_enabled" {
  description = "Whether to enable global write forwarding. Only supported on Aurora PostgreSQL."
  type        = bool
  default     = false
}

################################################################################
# Activity Streams
################################################################################

variable "activity_stream_enabled" {
  description = "Whether to enable Database Activity Streams on the Aurora cluster."
  type        = bool
  default     = false
}

variable "activity_stream_mode" {
  description = "The mode of the activity stream. Valid values: sync, async."
  type        = string
  default     = "async"

  validation {
    condition     = contains(["sync", "async"], var.activity_stream_mode)
    error_message = "Activity stream mode must be one of: sync, async."
  }
}

variable "activity_stream_kms_key_id" {
  description = "The ARN of the KMS key used to encrypt activity stream data. Required when activity_stream_enabled is true."
  type        = string
  default     = null

  validation {
    condition     = var.activity_stream_kms_key_id == null || can(regex("^arn:aws:kms:", var.activity_stream_kms_key_id))
    error_message = "Activity stream KMS key must be an ARN starting with 'arn:aws:kms:'."
  }
}

################################################################################
# IAM Role Associations
################################################################################

variable "iam_role_associations" {
  description = "Map of IAM role associations for the Aurora cluster. Supports features like S3_IMPORT, S3_EXPORT, LAMBDA_INVOKE, etc."
  type = map(object({
    role_arn     = string
    feature_name = string
  }))
  default = {}
}

################################################################################
# RDS Proxy
################################################################################

variable "proxy_creation_enabled" {
  type        = bool
  description = "Whether to create an RDS Proxy in front of the cluster. Requires master_user_password_management_enabled or proxy_auth_secret_arns."
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
