################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the collector's cluster, service and task family, and the prefix of every other resource this module creates. The collector's private DNS namespace is <name>.internal."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-54 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "VPC the collector runs in. Its private DNS namespace is associated with this VPC, so only this VPC resolves the collector's hostname."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a VPC ID starting with vpc-."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the collector tasks run in. The tasks get no public IP, so the subnets need a NAT gateway or VPC endpoints to reach X-Ray, CloudWatch Logs and the image registry."

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for subnet_id in var.subnet_ids : can(regex("^subnet-", subnet_id))])
    error_message = "The subnet_ids must name at least one subnet ID starting with subnet-."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups whose members may send OTLP to the collector on ports 4317 (gRPC) and 4318 (HTTP), in addition to members of the collector's client security group. Nothing else can reach the collector."
  default     = []

  validation {
    condition     = alltrue([for security_group_id in var.allowed_security_group_ids : can(regex("^sg-", security_group_id))])
    error_message = "Each allowed_security_group_ids entry must be a security group ID starting with sg-."
  }
}

################################################################################
# Task
################################################################################

variable "image" {
  type        = string
  description = "Collector image. It must be a build of the AWS Distro for OpenTelemetry collector, which reads its configuration from AOT_CONFIG_CONTENT and ships the /healthcheck binary."
  default     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.50.0"
}

variable "task_cpu" {
  type        = number
  description = "CPU units for each collector task (1024 is one vCPU). It must pair with task_memory as a valid Fargate size."
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "The task_cpu must be 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "task_memory" {
  type        = number
  description = "Memory in MiB for each collector task. The collector refuses new data once it uses 80% of it."
  default     = 1024

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 122880
    error_message = "The task_memory must be between 512 and 122880 MiB."
  }
}

variable "cpu_architecture" {
  type        = string
  description = "CPU architecture of the collector tasks: ARM64 or X86_64. The default image supports both, and ARM64 costs less."
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "The cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  type        = number
  description = "Number of collector tasks. Run two or more to keep accepting telemetry while a task is replaced or an Availability Zone fails."
  default     = 1

  validation {
    condition     = var.desired_count >= 1 && floor(var.desired_count) == var.desired_count
    error_message = "The desired_count must be a whole number of at least 1."
  }
}

################################################################################
# Metrics
################################################################################

variable "metrics_enabled" {
  type        = bool
  nullable    = false
  description = "Accept OTLP metrics and publish them to metrics_destination. While off, the collector rejects metric exports."
  default     = false
}

variable "metrics_destination" {
  type        = string
  nullable    = false
  description = "Where metrics go while metrics_enabled is true: cloudwatch publishes them as embedded metric format logs, each metric becoming a billed CloudWatch custom metric; prometheus remote-writes them to an Amazon Managed Service for Prometheus workspace."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "prometheus"], var.metrics_destination)
    error_message = "The metrics_destination must be cloudwatch or prometheus."
  }
}

variable "metrics_namespace" {
  type        = string
  description = "CloudWatch namespace for metrics sent to cloudwatch. Null names it after each sender's service.namespace and service.name resource attributes."
  default     = null
}

variable "prometheus_remote_write_url" {
  type        = string
  description = "Remote write URL of the Amazon Managed Service for Prometheus workspace that metrics go to when metrics_destination is prometheus."
  default     = null

  validation {
    condition     = !(var.metrics_enabled && var.metrics_destination == "prometheus") || can(regex("^https://aps-workspaces\\.[a-z0-9-]+\\.amazonaws\\.com/workspaces/ws-[a-z0-9-]+/api/v1/remote_write$", var.prometheus_remote_write_url))
    error_message = "Sending metrics to prometheus needs the workspace's remote write URL, https://aps-workspaces.<region>.amazonaws.com/workspaces/<workspace id>/api/v1/remote_write."
  }
}

variable "prometheus_workspace_arn" {
  type        = string
  description = "ARN of the Amazon Managed Service for Prometheus workspace that metrics go to when metrics_destination is prometheus. The task role may write to this workspace only."
  default     = null

  validation {
    condition     = !(var.metrics_enabled && var.metrics_destination == "prometheus") || can(regex("^arn:aws[a-z-]*:aps:[a-z0-9-]+:[0-9]{12}:workspace/ws-[a-z0-9-]+$", var.prometheus_workspace_arn))
    error_message = "Sending metrics to prometheus needs the workspace's ARN, arn:aws:aps:<region>:<account>:workspace/<workspace id>."
  }
}

################################################################################
# Logs
################################################################################

variable "logs_enabled" {
  type        = bool
  nullable    = false
  description = "Accept OTLP logs and write each log record, with its trace and span IDs, to a CloudWatch log group the module owns. While off, the collector rejects log exports."
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain the collector's own logs, the OTLP logs and the CloudWatch metric logs. Set to 0 to retain indefinitely."
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "The log_retention_days must be one of the values accepted by CloudWatch Logs (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653)."
  }
}
