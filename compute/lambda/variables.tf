################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the Lambda function."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64
    error_message = "The name must be between 1 and 64 characters."
  }
}

variable "description" {
  type        = string
  description = "Description of the Lambda function."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Lambda Function - Package and Runtime
################################################################################

variable "package_type" {
  type        = string
  description = "Lambda deployment package type. Valid values are 'Zip' and 'Image'."
  default     = "Zip"

  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "The package_type must be 'Zip' or 'Image'."
  }
}

variable "architecture" {
  type        = string
  description = "Instruction set architecture for the Lambda function."
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "The architecture must be either 'x86_64' or 'arm64'."
  }
}

variable "version_publishing_enabled" {
  type        = bool
  description = "Whether to publish a new Lambda version on each update."
  default     = false
}

variable "handler" {
  type        = string
  description = "Function entrypoint in your code. Required for Zip package type."
  default     = null
}

variable "runtime" {
  type        = string
  description = "Function runtime. Required for Zip package type."
  default     = null
}

variable "filename" {
  type        = string
  description = "Path to the local deployment package ZIP file."
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Base64-encoded SHA256 hash of the package file."
  default     = null
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket containing the deployment package."
  default     = null
}

variable "s3_key" {
  type        = string
  description = "S3 key of the deployment package."
  default     = null
}

variable "code_bucket_name" {
  type        = string
  description = "Name for the auto-created S3 bucket used to store the deployment package. Only used when package_type is 'Zip' and neither filename nor s3_bucket is provided. Defaults to '<name>-code-<account_id>'."
  default     = null
}

variable "code_bucket_force_destroy_enabled" {
  type        = bool
  description = "Whether the auto-created code bucket should be force-destroyed. Use with caution."
  default     = false
}

variable "placeholder_object_key" {
  type        = string
  description = "S3 key for the bootstrap package uploaded to the auto-created code bucket."
  default     = "bootstrap-package.zip"
}

variable "image_uri" {
  type        = string
  description = "Container image URI for Image package type."
  default     = null
}

variable "image_config" {
  type = object({
    command           = optional(list(string))
    entry_point       = optional(list(string))
    working_directory = optional(string)
  })
  description = "Container image configuration overrides."
  default     = null
}

################################################################################
# ECR Repository
################################################################################

variable "ecr_repository_creation_enabled" {
  type        = bool
  description = "Create an ECR repository for built container image package deployments."
  default     = false
}

variable "ecr_repository_name" {
  type        = string
  description = "Name of the ECR repository. If null, defaults to var.name."
  default     = null
}

variable "ecr_image_tag_mutability" {
  type        = string
  description = "Tag mutability setting for the ECR repository."
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "The ecr_image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "ecr_scan_on_push_enabled" {
  type        = bool
  description = "Scan images for vulnerabilities on push."
  default     = true
}

variable "ecr_force_deletion_enabled" {
  type        = bool
  description = "Allow the ECR repository to be deleted even when it contains images."
  default     = false
}

variable "ecr_default_lifecycle_policy_enabled" {
  type        = bool
  description = "Apply the submodule's built-in lifecycle policy for untagged and older tagged images."
  default     = false
}

################################################################################
# Lambda Function - Configuration
################################################################################

variable "memory_size" {
  type        = number
  description = "Amount of memory in MB for the Lambda function."
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "The memory_size must be between 128 and 10240 MB."
  }
}

variable "timeout" {
  type        = number
  description = "Function timeout in seconds."
  default     = 3

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "The timeout must be between 1 and 900 seconds."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt environment variables."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be null or a valid KMS key ARN."
  }
}

variable "layers" {
  type        = list(string)
  description = "List of Lambda layer ARNs."
  default     = []
}

variable "reserved_concurrent_executions" {
  type        = number
  description = "Reserved concurrent executions for the function. Use -1 to remove limits."
  default     = null

  validation {
    condition     = var.reserved_concurrent_executions == null || var.reserved_concurrent_executions >= -1
    error_message = "The reserved_concurrent_executions must be null or greater than or equal to -1."
  }
}

variable "ephemeral_storage_size" {
  type        = number
  description = "Size of /tmp directory in MB."
  default     = 512

  validation {
    condition     = var.ephemeral_storage_size >= 512 && var.ephemeral_storage_size <= 10240
    error_message = "The ephemeral_storage_size must be between 512 and 10240 MB."
  }
}

variable "tracing_mode" {
  type        = string
  description = "X-Ray tracing mode. Valid values are 'PassThrough' and 'Active'."
  default     = "PassThrough"

  validation {
    condition     = contains(["PassThrough", "Active"], var.tracing_mode)
    error_message = "The tracing_mode must be 'PassThrough' or 'Active'."
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables passed to the function."
  default     = {}
}

variable "vpc_config" {
  type = object({
    subnet_ids                  = list(string)
    security_group_ids          = list(string)
    ipv6_allowed_for_dual_stack = optional(bool)
  })
  description = "VPC configuration for the Lambda function."
  default     = null
}

variable "dead_letter_target_arn" {
  type        = string
  description = "Dead letter queue target ARN."
  default     = null

  validation {
    condition = (
      var.dead_letter_target_arn == null ||
      can(regex("^arn:aws:(sqs|sns):", var.dead_letter_target_arn))
    )
    error_message = "The dead_letter_target_arn must be null or a valid SQS/SNS ARN."
  }
}

variable "file_system_configs" {
  type = list(object({
    arn              = string
    local_mount_path = string
  }))
  description = "EFS access point and mount path configurations."
  default     = []
}

variable "snap_start_apply_on" {
  type        = string
  description = "SnapStart setting. Valid values are null and 'PublishedVersions'."
  default     = null

  validation {
    condition     = var.snap_start_apply_on == null || var.snap_start_apply_on == "PublishedVersions"
    error_message = "The snap_start_apply_on must be null or 'PublishedVersions'."
  }
}

variable "code_signing_config_arn" {
  type        = string
  description = "Code signing configuration ARN."
  default     = null
}

################################################################################
# IAM Role
################################################################################

variable "role_creation_enabled" {
  type        = bool
  description = "Whether to create an IAM role for the Lambda function."
  default     = true
}

variable "role_arn" {
  type        = string
  description = "Existing IAM role ARN to use when role_creation_enabled is false."
  default     = null

  validation {
    condition     = var.role_arn == null || can(regex("^arn:aws:iam::", var.role_arn))
    error_message = "The role_arn must be null or a valid IAM role ARN."
  }
}

variable "role_name" {
  type        = string
  description = "Custom IAM role name. If null and role_creation_enabled is true, defaults to '<name>-lambda-role'."
  default     = null
}

variable "role_path" {
  type        = string
  description = "Path for the IAM role."
  default     = "/"
}

variable "role_permissions_boundary" {
  type        = string
  description = "Permissions boundary ARN to use for the IAM role."
  default     = null
}

variable "basic_execution_policy_enabled" {
  type        = bool
  description = "Attach AWSLambdaBasicExecutionRole when creating the role."
  default     = true
}

variable "vpc_execution_policy_enabled" {
  type        = bool
  description = "Attach AWSLambdaVPCAccessExecutionRole when creating the role and vpc_config is set."
  default     = true
}

variable "role_managed_policy_arns" {
  type        = list(string)
  description = "Additional managed policy ARNs to attach to the created IAM role."
  default     = []
}

variable "role_inline_policies" {
  type        = map(string)
  description = "Inline policies to attach to the created IAM role. Map key is policy name, value is JSON policy."
  default     = {}
}

################################################################################
# CloudWatch Logs
################################################################################

variable "log_group_creation_enabled" {
  type        = bool
  description = "Whether to create the CloudWatch log group for the function."
  default     = true
}

variable "log_group_name" {
  type        = string
  description = "Custom CloudWatch log group name. If null, defaults to '/aws/lambda/<name>'."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days. Set to 0 for never expire."
  default     = 30

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "The log_retention_days must be a valid CloudWatch retention value."
  }
}

variable "log_kms_key_id" {
  type        = string
  description = "KMS key ID or ARN for log group encryption."
  default     = null
}

################################################################################
# Integrations - Permissions
################################################################################

variable "permissions" {
  type = list(object({
    statement_id           = optional(string)
    action                 = optional(string, "lambda:InvokeFunction")
    principal              = string
    source_arn             = optional(string)
    source_account         = optional(string)
    event_source_token     = optional(string)
    function_url_auth_type = optional(string)
    qualifier              = optional(string)
    principal_org_id       = optional(string)
  }))
  description = "Permission statements to create for invoking this function."
  default     = []
}

################################################################################
# Integrations - Event Source Mappings
################################################################################

variable "event_source_mappings" {
  type = list(object({
    event_source_arn                   = string
    enabled                            = optional(bool, true)
    batch_size                         = optional(number)
    maximum_batching_window_in_seconds = optional(number)
    starting_position                  = optional(string)
    starting_position_timestamp        = optional(string)
    parallelization_factor             = optional(number)
    maximum_record_age_in_seconds      = optional(number)
    bisect_batch_on_function_error     = optional(bool)
    maximum_retry_attempts             = optional(number)
    tumbling_window_in_seconds         = optional(number)
    function_response_types            = optional(list(string))
    queues                             = optional(list(string))
    topics                             = optional(list(string))

    source_access_configurations = optional(list(object({
      type = string
      uri  = string
    })), [])

    filter_criteria = optional(list(string), [])

    scaling_config_maximum_concurrency = optional(number)

    destination_config_on_failure_arn = optional(string)
  }))
  description = "Event source mappings for this Lambda function."
  default     = []
}

################################################################################
# Integrations - Aliases and URL
################################################################################

variable "aliases" {
  type = map(object({
    description                        = optional(string)
    function_version                   = optional(string)
    routing_additional_version_weights = optional(map(number), {})
  }))
  description = "Map of aliases to create, keyed by alias name."
  default     = {}
}

variable "function_url_enabled" {
  type        = bool
  description = "Whether to create a Lambda function URL."
  default     = false
}

variable "function_url_auth_type" {
  type        = string
  description = "Function URL authorization type. Valid values are 'NONE' and 'AWS_IAM'."
  default     = "AWS_IAM"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth_type)
    error_message = "The function_url_auth_type must be 'NONE' or 'AWS_IAM'."
  }
}

variable "function_url_invoke_mode" {
  type        = string
  description = "Function URL invoke mode. Valid values are 'BUFFERED' and 'RESPONSE_STREAM'."
  default     = "BUFFERED"

  validation {
    condition     = contains(["BUFFERED", "RESPONSE_STREAM"], var.function_url_invoke_mode)
    error_message = "The function_url_invoke_mode must be 'BUFFERED' or 'RESPONSE_STREAM'."
  }
}

variable "function_url_cors" {
  type = object({
    allow_credentials = optional(bool)
    allow_headers     = optional(list(string))
    allow_methods     = optional(list(string))
    allow_origins     = optional(list(string))
    expose_headers    = optional(list(string))
    max_age           = optional(number)
  })
  description = "CORS configuration for the function URL."
  default     = null
}

################################################################################
# Lambda@Edge
################################################################################

variable "lambda_at_edge_enabled" {
  type        = bool
  description = "Enable Lambda@Edge compatibility validations."
  default     = false
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# CloudWatch Alarms
################################################################################

variable "cloudwatch_alarms_creation_enabled" {
  type        = bool
  description = "Create a Lambda error-rate alarm in the function Region and any additional Edge execution Regions."
  default     = true
  nullable    = false
}

variable "cloudwatch_alarm_error_rate_threshold" {
  type        = number
  description = "Invocation error percentage at or above which the alarm fires."
  default     = 1
  nullable    = false
  validation {
    condition     = var.cloudwatch_alarm_error_rate_threshold > 0 && var.cloudwatch_alarm_error_rate_threshold <= 100
    error_message = "Error rate threshold must be greater than 0 and at most 100 percent."
  }
}

variable "cloudwatch_alarm_period" {
  type        = number
  description = "Metric aggregation period in seconds. Lambda publishes metrics at one-minute resolution."
  default     = 300
  nullable    = false
  validation {
    condition     = contains([60, 300, 900, 3600], var.cloudwatch_alarm_period)
    error_message = "Alarm period must be 60, 300, 900, or 3600 seconds."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  type        = number
  description = "Consecutive breaching periods required to alarm."
  default     = 1
  nullable    = false
  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1 && floor(var.cloudwatch_alarm_evaluation_periods) == var.cloudwatch_alarm_evaluation_periods && var.cloudwatch_alarm_evaluation_periods * var.cloudwatch_alarm_period <= 86400
    error_message = "Evaluation periods must be a positive integer covering at most one day."
  }
}

variable "cloudwatch_alarm_additional_regions" {
  type        = list(string)
  description = "Additional Lambda@Edge execution Regions to monitor. The function Region is always included. Add Regions as traffic expands. Regional Lambdas must leave this empty."
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for region in var.cloudwatch_alarm_additional_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))]) && (var.lambda_at_edge_enabled || length(var.cloudwatch_alarm_additional_regions) == 0)
    error_message = "Additional alarm Regions must be valid AWS Region names and can only be used with Lambda@Edge."
  }
}

variable "cloudwatch_alarm_actions" {
  type        = list(string)
  description = "Default action ARNs for ALARM transitions. SNS topics must be in the alarm Region; use the per-Region map for Edge alarms."
  default     = []
  nullable    = false
}

variable "cloudwatch_ok_actions" {
  type        = list(string)
  description = "Default action ARNs for OK transitions."
  default     = []
  nullable    = false
}

variable "cloudwatch_alarm_actions_by_region" {
  type        = map(list(string))
  description = "Per-Region ALARM action ARN overrides for Lambda@Edge. Empty entries support externally managed EventBridge notification relays."
  default     = {}
  nullable    = false
}

variable "cloudwatch_ok_actions_by_region" {
  type        = map(list(string))
  description = "Per-Region OK action ARN overrides for Lambda@Edge."
  default     = {}
  nullable    = false
}
