################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name for the target group, listener rule, and related resources."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,254}$", var.name))
    error_message = "The name must be 1-255 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the EKS cluster runs in. The target group must live in the same VPC as the pods it registers."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

################################################################################
# Fargate
################################################################################

variable "fargate_profile" {
  type = object({
    name       = string
    subnet_ids = list(string)
    selectors = list(object({
      namespace = string
      labels    = map(string)
    }))
  })
  description = "Optional EKS Fargate profile for this workload. Set to null to schedule without a workload-managed profile. EKS Fargate is on-demand only and requires private subnets."
  default     = null

  validation {
    condition     = var.fargate_profile == null || try(can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$", var.fargate_profile.name)), false)
    error_message = "The fargate_profile.name must be 1-63 alphanumeric, hyphen, or underscore characters and start with an alphanumeric character."
  }

  validation {
    condition     = var.fargate_profile == null || try(length(var.fargate_profile.selectors) >= 1, false)
    error_message = "The fargate_profile must include at least one selector."
  }

  validation {
    condition     = var.fargate_profile == null || var.cluster_name != null
    error_message = "The cluster_name must be set when fargate_profile is configured."
  }
}

################################################################################
# Target Group
################################################################################

variable "container_port" {
  type        = number
  description = "Port the application container listens on. The chart's Service targets this port and the AWS Load Balancer Controller registers pod IPs against it."
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "The container_port must be between 1 and 65535."
  }
}

variable "target_group_protocol" {
  type        = string
  description = "Protocol the load balancer uses to reach pods."
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_group_protocol)
    error_message = "The target_group_protocol must be HTTP or HTTPS."
  }
}

variable "target_group_deregistration_delay" {
  type        = number
  description = "Seconds the load balancer waits before deregistering a target, letting in-flight requests drain."
  default     = 300

  validation {
    condition     = var.target_group_deregistration_delay >= 0 && var.target_group_deregistration_delay <= 3600
    error_message = "The target_group_deregistration_delay must be between 0 and 3600."
  }
}

variable "target_group_slow_start" {
  type        = number
  description = "Seconds over which the load balancer ramps traffic to newly registered targets. Use 0 to disable."
  default     = 0

  validation {
    condition     = var.target_group_slow_start == 0 || (var.target_group_slow_start >= 30 && var.target_group_slow_start <= 900)
    error_message = "The target_group_slow_start must be 0 (disabled) or between 30 and 900."
  }
}

variable "target_group_health_check" {
  type = object({
    enabled             = optional(bool, true)
    path                = optional(string, "/")
    port                = optional(string, "traffic-port")
    protocol            = optional(string, null)
    matcher             = optional(string, "200-399")
    interval            = optional(number, 15)
    timeout             = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 2)
  })
  description = "Load balancer health check applied to the target group. Independent of the chart's Kubernetes readiness probe: this one decides whether the load balancer sends traffic to a pod."
  default     = {}

  validation {
    condition     = var.target_group_health_check.protocol == null || contains(["HTTP", "HTTPS"], coalesce(var.target_group_health_check.protocol, "HTTP"))
    error_message = "The target_group_health_check.protocol must be HTTP or HTTPS when set."
  }

  validation {
    condition     = var.target_group_health_check.timeout < var.target_group_health_check.interval
    error_message = "The target_group_health_check.timeout must be lower than target_group_health_check.interval."
  }
}

variable "target_group_stickiness" {
  type = object({
    enabled         = optional(bool, false)
    type            = optional(string, "lb_cookie")
    cookie_duration = optional(number, 86400)
    cookie_name     = optional(string, null)
  })
  description = "Target group cookie stickiness, keeping repeat requests on the same pod when possible."
  default     = {}

  validation {
    condition     = contains(["lb_cookie", "app_cookie"], var.target_group_stickiness.type)
    error_message = "The target_group_stickiness.type must be lb_cookie or app_cookie."
  }

  validation {
    condition     = !(var.target_group_stickiness.enabled && var.target_group_stickiness.type == "app_cookie") || try(length(var.target_group_stickiness.cookie_name), 0) > 0
    error_message = "The target_group_stickiness.cookie_name is required when target_group_stickiness.type is app_cookie."
  }
}

################################################################################
# Listener Rule
################################################################################

variable "listener_arn" {
  type        = string
  description = "ARN of the shared load balancer listener the rule is attached to. Comes from the EKS Add-ons module's public or private ALB. When null, no target group, listener rule, or load balancer lookup is created, which is how the worker and cron workloads use this module."
  default     = null

  validation {
    condition     = var.listener_arn == null || can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:", var.listener_arn))
    error_message = "The listener_arn must be an elasticloadbalancing ARN."
  }
}

variable "listener_rule_priority" {
  type        = number
  description = "Listener rule priority. When null, AWS assigns the next available priority."
  default     = null

  validation {
    condition     = var.listener_rule_priority == null || try(var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000, false)
    error_message = "The listener_rule_priority must be between 1 and 50000."
  }
}

variable "listener_rule_conditions" {
  type = list(object({
    type   = string
    values = list(string)
  }))
  description = "Conditions that route requests to this service. Supported types: host-header, path-pattern, http-header, http-request-method, query-string, source-ip. Defaults to a catch-all /* path rule."
  default = [{
    type   = "path-pattern"
    values = ["/*"]
  }]

  validation {
    condition     = length(var.listener_rule_conditions) > 0
    error_message = "At least one listener rule condition is required."
  }

  validation {
    condition = alltrue([
      for condition in var.listener_rule_conditions :
      contains(["host-header", "path-pattern", "http-header", "http-request-method", "query-string", "source-ip"], condition.type)
    ])
    error_message = "Each listener rule condition type must be one of: host-header, path-pattern, http-header, http-request-method, query-string, source-ip."
  }

  validation {
    condition = alltrue([
      for condition in var.listener_rule_conditions : length(condition.values) > 0
    ])
    error_message = "Each listener rule condition must have at least one value."
  }
}

################################################################################
# ECR Repository
################################################################################

variable "ecr_repository_creation_enabled" {
  type        = bool
  description = "Create an ECR repository for this workload's container image. When true, a repository is provisioned via the containers/ecr submodule."
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

variable "ecr_image_scan_on_push_enabled" {
  type        = bool
  description = "Scan images for vulnerabilities on push."
  default     = true
}

variable "ecr_force_delete_enabled" {
  type        = bool
  description = "Allow the ECR repository to be deleted even when it contains images."
  default     = false
}

variable "ecr_default_lifecycle_policy_enabled" {
  type        = bool
  description = "Apply the submodule's built-in lifecycle policy (expire untagged images and cap retained tagged images)."
  default     = false
}

################################################################################
# Workload release teardown
################################################################################

variable "workload_release_cleanup_enabled" {
  type        = bool
  description = "Uninstall the workload's Helm release when this stack is destroyed. Requires cluster_name, ravion_runner_role_arn, release_name and release_namespace."
  default     = false
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the workload runs on. Required when workload_release_cleanup_enabled is true or fargate_profile is set."
  default     = null
}

variable "ravion_runner_role_arn" {
  type        = string
  description = "ARN of the cluster's `<cluster>-ravion-runner` IAM role, assumed via `aws eks get-token` to reach the Kubernetes API when removing the release. Required when workload_release_cleanup_enabled is true."
  default     = null

  validation {
    condition     = var.ravion_runner_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.ravion_runner_role_arn))
    error_message = "ravion_runner_role_arn must be an IAM role ARN."
  }
}

variable "release_name" {
  type        = string
  description = "Name of the Helm release Ravion installs for this workload. Required when workload_release_cleanup_enabled is true."
  default     = null

  validation {
    condition     = var.release_name == null || can(regex("^[a-z0-9]([a-z0-9-]{0,51}[a-z0-9])?$", var.release_name))
    error_message = "release_name must be 1-53 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "release_namespace" {
  type        = string
  description = "Kubernetes namespace the Helm release is installed into. Required when workload_release_cleanup_enabled is true. The namespace itself is never removed; it may be shared."
  default     = null

  validation {
    condition     = var.release_namespace == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.release_namespace))
    error_message = "release_namespace must be 1-63 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "workload_release_helm_version" {
  type        = string
  description = "Helm version downloaded for the uninstall when no `helm` binary is on the PATH of the machine running `terraform destroy`."
  default     = "v4.2.4"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.workload_release_helm_version))
    error_message = "workload_release_helm_version must look like vX.Y.Z."
  }
}

variable "workload_release_uninstall_timeout" {
  type        = string
  description = "How long `helm uninstall --wait` waits for the workload's objects to be gone before the destroy fails."
  default     = "10m"
}
