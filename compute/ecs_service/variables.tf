################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name for the ECS service and related resources."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "The name must be between 1 and 255 characters."
  }
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
  description = "The ID of the VPC where the ECS service will run."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the ECS service tasks."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "public_ip_assignment_enabled" {
  type        = bool
  description = "Assign a public IP address to the ECS tasks. Required for Fargate tasks in public subnets without NAT."
  default     = false
}

################################################################################
# ECS Cluster
################################################################################

variable "cluster_arn" {
  type        = string
  description = "The ARN of the ECS cluster where the service will be deployed."

  validation {
    condition     = can(regex("^arn:aws:ecs:", var.cluster_arn))
    error_message = "The cluster_arn must be a valid ECS cluster ARN."
  }
}

################################################################################
# Task Definition
################################################################################

variable "task_cpu" {
  type        = number
  description = "The number of CPU units for the task (256, 512, 1024, 2048, 4096, 8192, 16384)."
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "The task_cpu must be one of: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }
}

variable "task_memory" {
  type        = number
  description = "The amount of memory (in MiB) for the task."
  default     = 512

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 122880
    error_message = "The task_memory must be between 512 and 122880 MiB."
  }
}

variable "task_ephemeral_storage_size_gib" {
  type        = number
  description = "The ephemeral storage size in GiB for Fargate tasks. Set to null to use the AWS default of 20 GiB."
  default     = null

  validation {
    condition     = var.task_ephemeral_storage_size_gib == null ? true : var.task_ephemeral_storage_size_gib >= 21 && var.task_ephemeral_storage_size_gib <= 200
    error_message = "The task_ephemeral_storage_size_gib must be null or between 21 and 200 GiB."
  }

  validation {
    condition     = var.task_ephemeral_storage_size_gib == null || (var.launch_type == "FARGATE" && contains(var.requires_compatibilities, "FARGATE"))
    error_message = "The task_ephemeral_storage_size_gib is only supported when launch_type is FARGATE and requires_compatibilities includes FARGATE."
  }
}

variable "launch_type" {
  type        = string
  description = "The launch type for the service (FARGATE or EC2)."
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "The launch_type must be either 'FARGATE' or 'EC2'."
  }
}

variable "network_mode" {
  type        = string
  description = "The Docker networking mode for the containers (awsvpc, bridge, host, none)."
  default     = "awsvpc"

  validation {
    condition     = contains(["awsvpc", "bridge", "host", "none"], var.network_mode)
    error_message = "The network_mode must be one of: awsvpc, bridge, host, none."
  }
}

variable "requires_compatibilities" {
  type        = list(string)
  description = "The launch type compatibility requirements for the task."
  default     = ["FARGATE"]

  validation {
    condition     = alltrue([for c in var.requires_compatibilities : contains(["FARGATE", "EC2", "EXTERNAL"], c)])
    error_message = "Each requires_compatibilities value must be one of: FARGATE, EC2, EXTERNAL."
  }
}

variable "runtime_platform" {
  type = object({
    operating_system_family = optional(string, "LINUX")
    cpu_architecture        = optional(string, "X86_64")
  })
  description = "The runtime platform configuration for the task."
  default     = {}

  validation {
    condition     = contains(["LINUX", "WINDOWS_SERVER_2019_FULL", "WINDOWS_SERVER_2019_CORE", "WINDOWS_SERVER_2022_FULL", "WINDOWS_SERVER_2022_CORE"], var.runtime_platform.operating_system_family)
    error_message = "The operating_system_family must be a valid OS family."
  }

  validation {
    condition     = contains(["X86_64", "ARM64"], var.runtime_platform.cpu_architecture)
    error_message = "The cpu_architecture must be either 'X86_64' or 'ARM64'."
  }
}

################################################################################
# Container Port
################################################################################

variable "container_port" {
  type        = number
  description = "The port the placeholder container listens on. The external deployment controller will update with the actual container configuration."
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "The container_port must be between 1 and 65535."
  }
}

################################################################################
# CloudWatch Logs
################################################################################

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs for the task. Set to 0 to retain indefinitely."
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "The log_retention_days must be one of the values accepted by CloudWatch Logs (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653)."
  }
}

variable "log_kms_key_id" {
  type        = string
  description = "The ARN of the KMS key to use for encrypting the CloudWatch log group. If null, logs are encrypted with the default CloudWatch encryption."
  default     = null
}

################################################################################
# Volumes
################################################################################

variable "volumes" {
  type = list(object({
    name = string

    efs_volume_configuration = optional(object({
      file_system_id          = string
      root_directory          = optional(string, "/")
      transit_encryption      = optional(string, "ENABLED")
      transit_encryption_port = optional(number, null)
      authorization_config = optional(object({
        access_point_id = optional(string, null)
        iam             = optional(string, "DISABLED")
      }), null)
    }), null)

    docker_volume_configuration = optional(object({
      scope         = optional(string, "task")
      autoprovision = optional(bool, false)
      driver        = optional(string, null)
      driver_opts   = optional(map(string), null)
      labels        = optional(map(string), null)
    }), null)
  }))
  description = "List of volume definitions for the task."
  default     = []
}

################################################################################
# IAM
################################################################################

variable "execution_role_arn" {
  type        = string
  description = "The ARN of an existing IAM role for task execution. If null, a role will be created."
  default     = null

  validation {
    condition     = var.execution_role_arn == null || can(regex("^arn:aws:iam::", var.execution_role_arn))
    error_message = "The execution_role_arn must be a valid IAM role ARN."
  }
}

variable "task_role_arn" {
  type        = string
  description = "The ARN of an existing IAM role for the task. If null, a role will be created."
  default     = null

  validation {
    condition     = var.task_role_arn == null || can(regex("^arn:aws:iam::", var.task_role_arn))
    error_message = "The task_role_arn must be a valid IAM role ARN."
  }
}

variable "task_role_policies" {
  type        = list(string)
  description = "List of IAM policy ARNs to attach to the task role (only used if task_role_arn is null)."
  default     = []

  validation {
    condition     = alltrue([for p in var.task_role_policies : can(regex("^arn:aws:iam::", p))])
    error_message = "All task_role_policies must be valid IAM policy ARNs."
  }
}

variable "task_role_inline_policies" {
  type        = any
  description = "Inline IAM policies to attach to the task role, keyed by policy name. Values are policy documents as HCL/JSON objects. Only used if task_role_arn is null."
  default     = {}

  validation {
    condition     = can(keys(var.task_role_inline_policies))
    error_message = "The task_role_inline_policies must be an object keyed by policy name."
  }
}

variable "execution_role_policies" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the execution role (only used if execution_role_arn is null)."
  default     = []

  validation {
    condition     = alltrue([for p in var.execution_role_policies : can(regex("^arn:aws:iam::", p))])
    error_message = "All execution_role_policies must be valid IAM policy ARNs."
  }
}

################################################################################
# ECS Service
################################################################################

variable "desired_count" {
  type        = number
  description = "The desired number of tasks to run. Defaults to 0 for infrastructure-first provisioning."
  default     = 0

  validation {
    condition     = var.desired_count >= 0
    error_message = "The desired_count must be 0 or greater."
  }
}

variable "deployment_type" {
  type        = string
  description = "Initial deployment strategy for direct Terraform use ('rolling', 'blue_green', 'linear', 'canary'). Ravion ECS Web stack provisioning passes 'rolling' and the Flightcontrol deploy manager passes the authoritative blue_green/linear/canary strategy on each UpdateService call, so strategy changes in Ravion do not require Terraform changes."
  default     = "rolling"

  validation {
    condition     = contains(["rolling", "blue_green", "linear", "canary"], var.deployment_type)
    error_message = "The deployment_type must be one of: 'rolling', 'blue_green', 'linear', 'canary'."
  }
}

variable "deployment_strategy_config" {
  type = object({
    # Minutes both revisions keep running after production traffic has
    # fully shifted, before the old revision is terminated.
    bake_time_in_minutes = optional(number, 10)

    # Canary tuning — only used when deployment_type is 'canary'.
    canary = optional(object({
      canary_percent              = optional(number, 5.0)
      canary_bake_time_in_minutes = optional(number, 10)
    }), {})

    # Linear tuning — only used when deployment_type is 'linear'.
    linear = optional(object({
      step_percent              = optional(number, 25.0)
      step_bake_time_in_minutes = optional(number, 5)
    }), {})
  })
  description = <<-EOT
    Initial tuning for direct Terraform use with native traffic-shift
    strategies (blue_green / linear / canary). Ravion ECS Web stack
    provisioning uses rolling and the Flightcontrol deploy manager passes
    the authoritative deploymentConfiguration (including pause lifecycle
    hooks) on every UpdateService call, so post-create changes to these
    values are ignored by Terraform (see ignore_changes on
    aws_ecs_service.this).
  EOT
  default     = {}
}

variable "test_listener_rule_arn" {
  type        = string
  description = "Optional ARN of an externally-managed ALB listener rule that routes test traffic for blue/green validation (drives the TEST_TRAFFIC_SHIFT lifecycle stages). Only used for native traffic-shift strategies when the module-created green listener rule is not enabled."
  default     = null
}

variable "green_alb_listener_rule_enabled" {
  type        = bool
  description = "Create a dedicated ALB listener rule that routes test traffic to the green (alternate) target group during native traffic-shift deployments (blue_green/linear/canary), so the new revision can be validated before production traffic shifts. The rule reuses the production listener and routing conditions plus a distinguishing test selector (query string by default, or header when test_traffic_condition_type is \"header\") and forwards to the alternate target group; the ECS deployment controller rewrites it through the TEST_TRAFFIC_SHIFT lifecycle stages. Created by default; no effect for NLB services."
  default     = true
}

variable "test_header_name" {
  type        = string
  description = "HTTP header name that distinguishes test traffic for the green listener rule. Requests carrying this header (with test_header_value) match the green rule and reach the alternate target group; requests without it fall through to production. Only used when green_alb_listener_rule_enabled is true and test_traffic_condition_type is \"header\"."
  default     = "X-Ravion-Test"
}

variable "test_header_value" {
  type        = string
  description = "Value paired with test_header_name for routing test traffic to the green target group. Only used when green_alb_listener_rule_enabled is true and test_traffic_condition_type is \"header\"."
  default     = "1"
}

variable "test_traffic_condition_type" {
  type        = string
  description = "Which request attribute distinguishes test traffic for the green listener rule: \"header\" (matches test_header_name/test_header_value) or \"query-string\" (matches test_query_string_key/test_query_string_value). ALB AND-combines conditions within a single rule and ECS native blue/green wires exactly one test rule, so the selector is one type per service, not both at once. Only used when green_alb_listener_rule_enabled is true."
  default     = "query-string"

  validation {
    condition     = contains(["header", "query-string"], var.test_traffic_condition_type)
    error_message = "test_traffic_condition_type must be either \"header\" or \"query-string\"."
  }
}

variable "test_query_string_key" {
  type        = string
  description = "Query-string key that distinguishes test traffic for the green listener rule (e.g. \"__x-rvn-test__\" matches ?__x-rvn-test__=...). Requests carrying this key/value match the green rule and reach the alternate target group; requests without it fall through to production. Only used when green_alb_listener_rule_enabled is true and test_traffic_condition_type is \"query-string\"."
  default     = "__x-rvn-test__"
}

variable "test_query_string_value" {
  type        = string
  description = "Value paired with test_query_string_key for routing test traffic to the green target group. Only used when green_alb_listener_rule_enabled is true and test_traffic_condition_type is \"query-string\"."
  default     = "1"
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  description = "The minimum healthy percent during deployment (rolling deployments only)."
  default     = 100

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 200
    error_message = "The deployment_minimum_healthy_percent must be between 0 and 200."
  }
}

variable "deployment_maximum_percent" {
  type        = number
  description = "The maximum percent during deployment (rolling deployments only)."
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100 && var.deployment_maximum_percent <= 400
    error_message = "The deployment_maximum_percent must be between 100 and 400."
  }
}

variable "execute_command_enabled" {
  type        = bool
  description = "Enable ECS Exec for debugging containers."
  default     = false
}

variable "new_deployment_forcing_enabled" {
  type        = bool
  description = "Force a new deployment of the service."
  default     = false
}

variable "steady_state_wait_enabled" {
  type        = bool
  description = "Wait for the service to reach a steady state before completing."
  default     = true
}

variable "health_check_grace_period_seconds" {
  type        = number
  description = "Seconds to ignore failing load balancer health checks on new tasks."
  default     = 0

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "The health_check_grace_period_seconds must be between 0 and 2147483647."
  }
}

variable "ecs_managed_tags_enabled" {
  type        = bool
  description = "Enable Amazon ECS managed tags for the tasks."
  default     = true
}

variable "propagate_tags" {
  type        = string
  description = "Whether to propagate tags from the task definition or service to tasks."
  default     = "SERVICE"

  validation {
    condition     = contains(["TASK_DEFINITION", "SERVICE", "NONE"], var.propagate_tags)
    error_message = "The propagate_tags must be one of: TASK_DEFINITION, SERVICE, NONE."
  }
}

variable "platform_version" {
  type        = string
  description = "The platform version for Fargate tasks."
  default     = "LATEST"
}

variable "capacity_provider_strategies" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  description = "Capacity provider strategies for the service. If empty, uses launch_type instead."
  default     = []
}

################################################################################
# Security Group
################################################################################

variable "security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs to attach to the ECS tasks."
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group ID of the load balancer. When provided, the ECS service ingress rule allows traffic only from this SG instead of the VPC CIDR."
  default     = null

  validation {
    condition     = var.load_balancer_security_group_id == null || can(regex("^sg-", var.load_balancer_security_group_id))
    error_message = "The load_balancer_security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "load_balancer_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access service-created NLB listeners. Only used when load_balancer_attachment.nlb_listeners is set and load_balancer_security_group_id is provided."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.load_balancer_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All load_balancer_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "load_balancer_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access service-created NLB listeners. Only used when load_balancer_attachment.nlb_listeners is set and load_balancer_security_group_id is provided."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.load_balancer_ingress_ipv6_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All load_balancer_ingress_ipv6_cidr_blocks must be valid IPv6 CIDR blocks."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access the service (in addition to load balancer)."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

################################################################################
# Load Balancer
################################################################################

variable "load_balancer_attachment" {
  type = object({
    enabled = optional(bool, true)

    target_group = object({
      port                 = number
      protocol             = optional(string, "HTTP") # HTTP, HTTPS for ALB; TCP, UDP, TLS for NLB
      target_type          = optional(string, "ip")
      deregistration_delay = optional(number, 300)
      slow_start           = optional(number, 0) # Only applicable for ALB (HTTP/HTTPS)

      health_check = optional(object({
        enabled             = optional(bool, true)
        path                = optional(string, "/") # Only applicable for HTTP/HTTPS
        port                = optional(string, "traffic-port")
        protocol            = optional(string, null)
        matcher             = optional(string, "200") # Only applicable for HTTP/HTTPS
        interval            = optional(number, 30)
        timeout             = optional(number, 5)
        healthy_threshold   = optional(number, 3)
        unhealthy_threshold = optional(number, 3)
      }), {})

      stickiness = optional(object({
        enabled         = optional(bool, false)
        type            = string                  # lb_cookie or app_cookie for ALB; source_ip for NLB
        cookie_duration = optional(number, 86400) # Only applicable for ALB (lb_cookie/app_cookie)
        cookie_name     = optional(string, null)  # Only applicable for ALB (app_cookie)
      }), null)
    })

    # ALB: Listener rules (attach to existing ALB listener)
    #
    # IMPORTANT: only the first rule is wired into the service's
    # advanced_configuration as the production listener rule. Native
    # traffic-shift deployments (blue_green/linear/canary) rewrite only
    # that rule — traffic on any additional rules never shifts to the
    # new revision. Terraform rejects >1 rule when deployment_type is a
    # traffic-shift strategy, but because the strategy is a
    # per-deployment decision on the native ECS controller, services
    # that may ever deploy with a traffic-shift strategy must also keep
    # to a single rule.
    listener_rules = optional(list(object({
      listener_arn = string
      priority     = optional(number, null) # null = AWS auto-assigns next available priority

      conditions = list(object({
        type   = string
        values = list(string)
      }))

      # Optional: for weighted target groups
      weight = optional(number, 100)
    })), [])

    # NLB: Rolling-only listener configuration. The first listener uses
    # the production target group above; each later listener gets its own
    # target group and ECS load-balancer attachment.
    nlb_listeners = optional(list(object({
      nlb_arn         = string
      port            = number
      protocol        = string
      container_port  = number
      target_protocol = string
      certificate_arn = optional(string)
      ssl_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
      alpn_policy     = optional(string)
    })), [])

    container_name = optional(string, null)
    container_port = optional(number, null)
  })
  description = "Load balancer configuration including target groups, ALB listener rules, and NLB listeners."
  default     = null

  validation {
    condition = var.load_balancer_attachment == null || contains(
      ["HTTP", "HTTPS", "TCP", "UDP", "TLS", "TCP_UDP", "GENEVE"],
      var.load_balancer_attachment.target_group.protocol
    )
    error_message = "The protocol must be one of: HTTP, HTTPS (for ALB), or TCP, UDP, TLS, TCP_UDP, GENEVE (for NLB/GWLB)."
  }

  validation {
    condition = var.load_balancer_attachment == null || (
      !var.load_balancer_attachment.enabled
      || length(var.load_balancer_attachment.listener_rules) > 0
      || length(var.load_balancer_attachment.nlb_listeners) > 0
      || (var.cluster_parent_fqdn != null && var.cluster_parent_fqdn != "")
    )
    error_message = "An enabled load_balancer_attachment requires listener_rules for ALB, nlb_listeners for NLB, or cluster_parent_fqdn for Ravion-managed routing."
  }

  validation {
    condition     = var.load_balancer_attachment == null || length(var.load_balancer_attachment.listener_rules) == 0 || length(var.load_balancer_attachment.nlb_listeners) == 0
    error_message = "Set listener_rules for ALB or nlb_listeners for NLB, not both."
  }

  validation {
    condition = var.load_balancer_attachment == null || alltrue([
      for listener in var.load_balancer_attachment.nlb_listeners :
      contains(["TCP", "TLS", "UDP"], listener.protocol)
    ])
    error_message = "Each nlb_listeners protocol must be TCP, TLS, or UDP."
  }

  validation {
    condition = var.load_balancer_attachment == null || alltrue([
      for listener in var.load_balancer_attachment.nlb_listeners :
      listener.port >= 1 && listener.port <= 65535 && listener.container_port >= 1 && listener.container_port <= 65535
    ])
    error_message = "Each nlb_listeners port and container_port must be between 1 and 65535."
  }

  validation {
    condition = var.load_balancer_attachment == null || length(distinct([
      for listener in var.load_balancer_attachment.nlb_listeners : listener.port
    ])) == length(var.load_balancer_attachment.nlb_listeners)
    error_message = "Each nlb_listeners port must be unique."
  }

  validation {
    condition = var.load_balancer_attachment == null || length(distinct([
      for listener in var.load_balancer_attachment.nlb_listeners :
      listener.container_port
    ])) == length(var.load_balancer_attachment.nlb_listeners)
    error_message = "Each nlb_listeners container_port must be unique."
  }

  validation {
    condition     = var.load_balancer_attachment == null || length(var.load_balancer_attachment.nlb_listeners) <= 5
    error_message = "nlb_listeners supports at most five listeners, matching the ECS service target group limit."
  }

  validation {
    condition = var.load_balancer_attachment == null || length(var.load_balancer_attachment.nlb_listeners) == 0 || alltrue([
      for listener in var.load_balancer_attachment.nlb_listeners :
      listener.nlb_arn == var.load_balancer_attachment.nlb_listeners[0].nlb_arn
    ])
    error_message = "All nlb_listeners must use the same NLB ARN."
  }

  validation {
    condition = var.load_balancer_attachment == null || alltrue([
      for listener in var.load_balancer_attachment.nlb_listeners :
      listener.protocol != "TLS" || try(length(listener.certificate_arn) > 0, false)
    ])
    error_message = "Each TLS listener in nlb_listeners requires certificate_arn."
  }

  validation {
    condition = var.load_balancer_attachment == null || alltrue([
      for listener in var.load_balancer_attachment.nlb_listeners :
      listener.protocol == "TLS"
      ? contains(["TCP", "TLS"], listener.target_protocol)
      : listener.target_protocol == listener.protocol
    ])
    error_message = "TLS listeners must use TCP or TLS as target_protocol; TCP and UDP listeners must use the same target protocol as the listener."
  }

  validation {
    condition = var.load_balancer_attachment == null || var.load_balancer_attachment.target_group.stickiness == null || (
      contains(["HTTP", "HTTPS"], var.load_balancer_attachment.target_group.protocol)
      ? contains(["lb_cookie", "app_cookie"], var.load_balancer_attachment.target_group.stickiness.type)
      : var.load_balancer_attachment.target_group.stickiness.type == "source_ip"
    )
    error_message = "Stickiness type must be 'lb_cookie' or 'app_cookie' for ALB (HTTP/HTTPS), or 'source_ip' for NLB (TCP/UDP/TLS)."
  }
}

################################################################################
# Auto Scaling
################################################################################

variable "auto_scaling" {
  type = object({
    enabled      = optional(bool, true)
    min_capacity = number
    max_capacity = number

    target_tracking = optional(list(object({
      policy_name       = string
      target_value      = number
      predefined_metric = optional(string, null)
      custom_metric = optional(object({
        metric_name = string
        namespace   = string
        statistic   = string
        dimensions  = optional(map(string), {})
      }), null)
      scale_in_cooldown  = optional(number, 300)
      scale_out_cooldown = optional(number, 300)
      scale_in_enabled   = optional(bool, true)
    })), [])

    scheduled = optional(list(object({
      name         = string
      schedule     = string
      min_capacity = optional(number, null)
      max_capacity = optional(number, null)
      timezone     = optional(string, "UTC")
      start_time   = optional(string, null)
      end_time     = optional(string, null)
    })), [])
  })
  description = "Auto scaling configuration for the service."
  default     = null
}

################################################################################
# Service Discovery
################################################################################

variable "service_discovery" {
  type = object({
    namespace_id    = string
    dns_record_type = optional(string, "A")
    dns_ttl         = optional(number, 10)
    routing_policy  = optional(string, "MULTIVALUE")

    health_check_custom_config = optional(object({
      failure_threshold = optional(number, 1)
    }), null)
  })
  description = "AWS Cloud Map service discovery configuration."
  default     = null
}

################################################################################
# Circuit Breaker
################################################################################

variable "deployment_circuit_breaker" {
  type = object({
    enable   = bool
    rollback = bool
  })
  description = "Deployment circuit breaker configuration."
  default = {
    enable   = true
    rollback = true
  }
}

################################################################################
# ECR Repository
################################################################################

variable "ecr_repository_creation_enabled" {
  type        = bool
  description = "Create an ECR repository for this service's container image. When true, a repository is provisioned via the containers/ecr submodule."
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
  description = "Apply the submodule's built-in lifecycle policy (expire untagged images and cap retained tagged images)."
  default     = false
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Ravion-managed domains (optional)
################################################################################

variable "cluster_parent_fqdn" {
  type        = string
  description = "Cluster wildcard apex FQDN (pipe from ecs_cluster.ravion_cluster_domain_fqdn). Set to enable Ravion-managed domains for this service."
  default     = null
}

variable "cluster_https_listener_arn" {
  type        = string
  description = "Cluster ALB HTTPS listener ARN this service attaches to. Pipe ecs_cluster.public_alb_https_listener_arn for a public service, or private_alb_https_listener_arn for a private one. Required when cluster_parent_fqdn is set."
  default     = null
}

variable "ravion_listener_rule_priority" {
  type        = number
  description = "Listener rule priority (1-50000). 0 = auto-derive from sha256(name)."
  default     = 0
}

variable "domains" {
  type        = list(string)
  description = "Service FQDNs. Each entry that is one label under the cluster apex (<leaf>.<apex>) rides the cluster wildcard cert; any other (custom/external) entry is covered by a per-service instance cert (max 10 custom). Empty = an auto-FQDN <given-id>.<apex> under the cluster wildcard."
  default     = []
}

variable "cluster_alb_dns_name" {
  type        = string
  description = "Cluster ALB DNS name for Mode B routing records — public_alb_dns_name for a public service, private_alb_dns_name for a private one. Must match the ALB whose listener is in cluster_https_listener_arn."
  default     = null
}

variable "cluster_alb_zone_id" {
  type        = string
  description = "Cluster ALB hosted zone id for Mode B routing records — public_alb_zone_id for a public service, private_alb_zone_id for a private one. Must match the ALB whose listener is in cluster_https_listener_arn."
  default     = null
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion AwsAccount row id (aws_*). Required for Mode B."
  default     = null
}

variable "module_instance_given_id" {
  type        = string
  description = "The module instance's user-facing given id (injected by the runner as TF_VAR_module_instance_given_id). Used as the auto-FQDN leaf under the cluster wildcard."
  default     = null
}

variable "module_instance_id" {
  type        = string
  description = "The Ravion module instance id (minst_*) that owns this service's Ravion-managed domains/certificate. Injected by the runner as TF_VAR_module_instance_id inside a stack run; set it explicitly for external/API-key runs. Required when use_ravion_managed_domains = true."
  default     = null
}

variable "ravion_aws_region" {
  type        = string
  description = "AWS region the per-service cert lives in. Defaults to the module region."
  default     = null
}
