################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module. Also used as the DB proxy name."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 60
    error_message = "The name must be between 1 and 60 characters."
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
# Proxy
################################################################################

variable "engine_family" {
  type        = string
  description = "The kind of database engine the proxy connects to: MYSQL (also used for MariaDB), POSTGRESQL, or SQLSERVER."

  validation {
    condition     = contains(["MYSQL", "POSTGRESQL", "SQLSERVER"], var.engine_family)
    error_message = "The engine_family must be one of: MYSQL, POSTGRESQL, SQLSERVER."
  }
}

variable "tls_requirement_enabled" {
  type        = bool
  description = "Whether Transport Layer Security (TLS) encryption is required for connections to the proxy."
  default     = true
}

variable "debug_logging_enabled" {
  type        = bool
  description = "Whether the proxy logs detailed connection information, including SQL statements, to CloudWatch Logs."
  default     = false
}

variable "idle_client_timeout" {
  type        = number
  description = "The number of seconds a client connection can be idle before the proxy disconnects it."
  default     = 1800

  validation {
    condition     = var.idle_client_timeout >= 1 && var.idle_client_timeout <= 28800
    error_message = "The idle_client_timeout must be between 1 and 28800 seconds."
  }
}

################################################################################
# Authentication
################################################################################

variable "auth" {
  type = list(object({
    secret_arn                = string
    description               = optional(string)
    username                  = optional(string)
    iam_auth                  = optional(string, "DISABLED")
    client_password_auth_type = optional(string)
  }))
  description = "List of authentication configurations for the proxy. Each entry references a Secrets Manager secret containing database credentials. iam_auth may be DISABLED, REQUIRED, or ENABLED."

  validation {
    condition     = length(var.auth) > 0
    error_message = "At least one auth configuration is required."
  }

  validation {
    condition     = alltrue([for a in var.auth : startswith(a.secret_arn, "arn:")])
    error_message = "Each auth secret_arn must be a valid Secrets Manager secret ARN."
  }

  validation {
    condition     = alltrue([for a in var.auth : contains(["DISABLED", "REQUIRED", "ENABLED"], a.iam_auth)])
    error_message = "Each auth iam_auth must be one of: DISABLED, REQUIRED, ENABLED."
  }
}

variable "secret_kms_key_arns" {
  type        = list(string)
  description = "List of KMS key ARNs used to encrypt the auth secrets. Required for the proxy IAM role to decrypt secrets encrypted with a customer-managed key. Not needed for the default aws/secretsmanager key."
  default     = []

  validation {
    condition     = alltrue([for arn in var.secret_kms_key_arns : startswith(arn, "arn:")])
    error_message = "All secret_kms_key_arns must be valid KMS key ARNs."
  }
}

################################################################################
# Target
################################################################################

variable "db_instance_identifier" {
  type        = string
  description = "The identifier of an RDS DB instance to register as the proxy target. Exactly one of db_instance_identifier or db_cluster_identifier must be provided."
  default     = null
}

variable "db_cluster_identifier" {
  type        = string
  description = "The identifier of an Aurora DB cluster to register as the proxy target. Exactly one of db_instance_identifier or db_cluster_identifier must be provided."
  default     = null
}

################################################################################
# Connection Pool
################################################################################

variable "connection_borrow_timeout" {
  type        = number
  description = "The number of seconds the proxy waits for a connection to become available in the connection pool before returning a timeout error."
  default     = 120

  validation {
    condition     = var.connection_borrow_timeout >= 0
    error_message = "The connection_borrow_timeout must be greater than or equal to 0."
  }
}

variable "init_query" {
  type        = string
  description = "One or more SQL statements for the proxy to run when opening each new database connection."
  default     = null
}

variable "max_connections_percent" {
  type        = number
  description = "The maximum size of the connection pool as a percentage of the max_connections setting of the target database."
  default     = 100

  validation {
    condition     = var.max_connections_percent >= 1 && var.max_connections_percent <= 100
    error_message = "The max_connections_percent must be between 1 and 100."
  }
}

variable "max_idle_connections_percent" {
  type        = number
  description = "The maximum percentage of idle database connections the proxy keeps open, as a percentage of the max_connections setting of the target database."
  default     = 50

  validation {
    condition     = var.max_idle_connections_percent >= 0 && var.max_idle_connections_percent <= 100
    error_message = "The max_idle_connections_percent must be between 0 and 100."
  }

  validation {
    condition     = var.max_idle_connections_percent <= var.max_connections_percent
    error_message = "The max_idle_connections_percent must be less than or equal to max_connections_percent."
  }
}

variable "session_pinning_filters" {
  type        = list(string)
  description = "Each item in the list identifies a class of SQL operations that normally cause all later statements in a session to be pinned to the same database connection. Valid value: EXCLUDE_VARIABLE_SETS."
  default     = []

  validation {
    condition     = alltrue([for f in var.session_pinning_filters : f == "EXCLUDE_VARIABLE_SETS"])
    error_message = "The only valid session pinning filter is EXCLUDE_VARIABLE_SETS."
  }
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the proxy will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the proxy. At least two subnets in different AZs are required."

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
  description = "The port on which the proxy accepts connections. If not specified, defaults based on engine_family (3306 for MYSQL, 5432 for POSTGRESQL, 1433 for SQLSERVER). Used for security group rules."
  default     = null

  validation {
    condition     = var.port == null || (var.port >= 1 && var.port <= 65535)
    error_message = "The port must be between 1 and 65535."
  }
}

################################################################################
# Security Group
################################################################################

variable "security_group_creation_enabled" {
  type        = bool
  description = "Whether to create a new security group for the proxy."
  default     = true
}

variable "security_group_id" {
  type        = string
  description = "The ID of an existing security group to use for the proxy. Required if security_group_creation_enabled is false."
  default     = null

  validation {
    condition     = var.security_group_id == null || can(regex("^sg-", var.security_group_id))
    error_message = "The security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "List of security group IDs allowed to connect to the proxy."
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All allowed_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to connect to the proxy."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_cidr_blocks must be valid CIDR blocks."
  }
}

################################################################################
# IAM
################################################################################

variable "iam_role_creation_enabled" {
  type        = bool
  description = "Whether to create the IAM role the proxy uses to read credentials from Secrets Manager."
  default     = true
}

variable "iam_role_arn" {
  type        = string
  description = "The ARN of an existing IAM role for the proxy to use. Required if iam_role_creation_enabled is false."
  default     = null

  validation {
    condition     = var.iam_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::", var.iam_role_arn))
    error_message = "The iam_role_arn must be a valid IAM role ARN."
  }
}

################################################################################
# Region
################################################################################

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
