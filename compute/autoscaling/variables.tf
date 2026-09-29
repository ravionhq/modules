################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name for resources created by this module, including the Auto Scaling Group unless name_prefix is set."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "The name must be between 1 and 255 characters."
  }
}

variable "name_prefix" {
  type        = string
  description = "Optional prefix for a generated Auto Scaling Group name. Use this instead of a fixed group name to allow create-before-destroy replacement."
  default     = null

  validation {
    condition     = var.name_prefix == null || (length(var.name_prefix) > 0 && length(var.name_prefix) <= 200)
    error_message = "The name_prefix must be null or between 1 and 200 characters to leave room for the generated suffix."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Auto Scaling Group - Core Configuration
################################################################################

variable "min_size" {
  type        = number
  description = "The minimum number of instances in the Auto Scaling Group."
  default     = 0

  validation {
    condition     = var.min_size >= 0
    error_message = "The min_size must be 0 or greater."
  }
}

variable "max_size" {
  type        = number
  description = "The maximum number of instances in the Auto Scaling Group."
  default     = 10

  validation {
    condition     = var.max_size >= 1
    error_message = "The max_size must be at least 1."
  }
}

variable "desired_capacity" {
  type        = number
  description = "The initial desired number of instances in the Auto Scaling Group. If null, defaults to min_size. Note: Changes to this value are ignored after creation to support external scaling mechanisms (ECS capacity providers, scaling policies, scheduled actions). To adjust capacity, use scaling policies or update min_size."
  default     = null

  validation {
    condition     = var.desired_capacity == null || var.desired_capacity >= 0
    error_message = "The desired_capacity must be null or 0 or greater."
  }
}

variable "vpc_zone_identifier" {
  type        = list(string)
  description = "A list of subnet IDs where the Auto Scaling Group will launch instances."

  validation {
    condition     = length(var.vpc_zone_identifier) > 0
    error_message = "At least one subnet ID must be provided in vpc_zone_identifier."
  }

  validation {
    condition     = alltrue([for s in var.vpc_zone_identifier : can(regex("^subnet-", s))])
    error_message = "All vpc_zone_identifier values must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# Auto Scaling Group - Timing and Cooldown
################################################################################

variable "default_cooldown" {
  type        = number
  description = "The amount of time, in seconds, after a scaling activity completes before another scaling activity can start."
  default     = 300

  validation {
    condition     = var.default_cooldown >= 0
    error_message = "The default_cooldown must be 0 or greater."
  }
}

variable "default_instance_warmup" {
  type        = number
  description = "The amount of time, in seconds, until a newly launched instance can contribute to CloudWatch metrics. If null, the value of default_cooldown is used."
  default     = null

  validation {
    condition     = var.default_instance_warmup == null || var.default_instance_warmup >= 0
    error_message = "The default_instance_warmup must be null or 0 or greater."
  }
}

variable "wait_for_capacity_timeout" {
  type        = string
  description = "The maximum duration to wait for ASG instances to become healthy. Set to '0' to disable."
  default     = "10m"
}

################################################################################
# Auto Scaling Group - Instance Protection and Lifecycle
################################################################################

variable "scale_in_protection_enabled" {
  type        = bool
  description = "Whether newly launched instances are protected from scale in by default."
  default     = false
}

variable "max_instance_lifetime" {
  type        = number
  description = "The maximum amount of time, in seconds, that an instance can be in service. Must be 0 or between 86400 (1 day) and 31536000 (365 days). Set to 0 to disable."
  default     = null

  validation {
    condition     = var.max_instance_lifetime == null || var.max_instance_lifetime == 0 || (var.max_instance_lifetime >= 86400 && var.max_instance_lifetime <= 31536000)
    error_message = "The max_instance_lifetime must be null, 0, or between 86400 (1 day) and 31536000 (365 days)."
  }
}

variable "force_delete_enabled" {
  type        = bool
  description = "Whether to force delete the Auto Scaling Group without waiting for instances to terminate."
  default     = false
}

################################################################################
# Auto Scaling Group - Health Checks
################################################################################

variable "health_check_type" {
  type        = string
  description = "The type of health check to perform. Valid values are 'EC2' or 'ELB'."
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "The health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  type        = number
  description = "The time, in seconds, to wait after instance launch before checking health."
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "The health_check_grace_period must be 0 or greater."
  }
}

################################################################################
# Auto Scaling Group - Capacity and Scaling Behavior
################################################################################

variable "capacity_rebalance_enabled" {
  type        = bool
  description = "Whether to enable capacity rebalancing for Spot instances when they receive a rebalance recommendation."
  default     = false
}

variable "termination_policies" {
  type        = list(string)
  description = "A list of policies to determine which instances to terminate first during scale in. Valid values: 'OldestInstance', 'NewestInstance', 'OldestLaunchConfiguration', 'OldestLaunchTemplate', 'ClosestToNextInstanceHour', 'AllocationStrategy', 'Default'."
  default     = ["Default"]

  validation {
    condition = alltrue([
      for policy in var.termination_policies :
      contains(["OldestInstance", "NewestInstance", "OldestLaunchConfiguration", "OldestLaunchTemplate", "ClosestToNextInstanceHour", "AllocationStrategy", "Default"], policy)
    ])
    error_message = "Each termination_policy must be one of: 'OldestInstance', 'NewestInstance', 'OldestLaunchConfiguration', 'OldestLaunchTemplate', 'ClosestToNextInstanceHour', 'AllocationStrategy', 'Default'."
  }
}

variable "suspended_processes" {
  type        = list(string)
  description = "A list of Auto Scaling processes to suspend. Valid values: 'Launch', 'Terminate', 'HealthCheck', 'ReplaceUnhealthy', 'AZRebalance', 'AlarmNotification', 'ScheduledActions', 'AddToLoadBalancer', 'InstanceRefresh'."
  default     = []

  validation {
    condition = alltrue([
      for process in var.suspended_processes :
      contains(["Launch", "Terminate", "HealthCheck", "ReplaceUnhealthy", "AZRebalance", "AlarmNotification", "ScheduledActions", "AddToLoadBalancer", "InstanceRefresh"], process)
    ])
    error_message = "Each suspended_process must be one of: 'Launch', 'Terminate', 'HealthCheck', 'ReplaceUnhealthy', 'AZRebalance', 'AlarmNotification', 'ScheduledActions', 'AddToLoadBalancer', 'InstanceRefresh'."
  }
}

################################################################################
# Auto Scaling Group - CloudWatch Metrics
################################################################################

variable "enabled_metrics" {
  type        = list(string)
  description = "A list of CloudWatch metrics to enable for the Auto Scaling Group. Valid values: 'GroupMinSize', 'GroupMaxSize', 'GroupDesiredCapacity', 'GroupInServiceInstances', 'GroupPendingInstances', 'GroupStandbyInstances', 'GroupTerminatingInstances', 'GroupTotalInstances', 'GroupInServiceCapacity', 'GroupPendingCapacity', 'GroupStandbyCapacity', 'GroupTerminatingCapacity', 'GroupTotalCapacity', 'WarmPoolDesiredCapacity', 'WarmPoolWarmedCapacity', 'WarmPoolPendingCapacity', 'WarmPoolTerminatingCapacity', 'WarmPoolTotalCapacity', 'GroupAndWarmPoolDesiredCapacity', 'GroupAndWarmPoolTotalCapacity'."
  default     = []

  validation {
    condition = alltrue([
      for metric in var.enabled_metrics :
      contains([
        "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances",
        "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances",
        "GroupInServiceCapacity", "GroupPendingCapacity", "GroupStandbyCapacity", "GroupTerminatingCapacity",
        "GroupTotalCapacity", "WarmPoolDesiredCapacity", "WarmPoolWarmedCapacity", "WarmPoolPendingCapacity",
        "WarmPoolTerminatingCapacity", "WarmPoolTotalCapacity", "GroupAndWarmPoolDesiredCapacity", "GroupAndWarmPoolTotalCapacity"
      ], metric)
    ])
    error_message = "Each enabled_metric must be a valid CloudWatch metric name for Auto Scaling Groups."
  }
}

variable "metrics_granularity" {
  type        = string
  description = "The granularity to associate with the metrics. The only valid value is '1Minute'."
  default     = "1Minute"

  validation {
    condition     = var.metrics_granularity == "1Minute"
    error_message = "The metrics_granularity must be '1Minute'."
  }
}

################################################################################
# Auto Scaling Group - Service-Linked Role
################################################################################

variable "service_linked_role_arn" {
  type        = string
  description = "The ARN of a custom service-linked role for the Auto Scaling Group. If not specified, the default role is used."
  default     = null

  validation {
    condition     = var.service_linked_role_arn == null || can(regex("^arn:aws:iam::", var.service_linked_role_arn))
    error_message = "The service_linked_role_arn must be null or a valid IAM role ARN starting with 'arn:aws:iam::'."
  }
}

################################################################################
# Auto Scaling Group - Load Balancer Integration
################################################################################

variable "target_group_arns" {
  type        = list(string)
  description = "A list of target group ARNs to associate with the Auto Scaling Group."
  default     = []

  validation {
    condition = alltrue([
      for arn in var.target_group_arns :
      can(regex("^arn:aws:elasticloadbalancing:", arn))
    ])
    error_message = "All target_group_arns must be valid Elastic Load Balancing ARNs starting with 'arn:aws:elasticloadbalancing:'."
  }
}

################################################################################
# Auto Scaling Group - ECS Integration
################################################################################

variable "ecs_managed_tag_enabled" {
  type        = bool
  description = "Whether to add the 'AmazonECSManaged' tag for ECS capacity provider integration."
  default     = false
}

################################################################################
# Auto Scaling Group - Tag Propagation
################################################################################

variable "tag_propagation_at_launch_enabled" {
  type        = bool
  description = "Whether to propagate tags from the Auto Scaling Group to launched instances."
  default     = true
}

################################################################################
# Launch Template - Configuration
################################################################################

variable "launch_template_creation_enabled" {
  type        = bool
  description = "Whether to create a launch template. Set to false when using an external launch template."
  default     = true
}

variable "launch_template_id" {
  type        = string
  description = "The ID of an existing launch template to use. Required if launch_template_creation_enabled is false and launch_template_name is not provided."
  default     = null

  validation {
    condition     = var.launch_template_id == null || can(regex("^lt-", var.launch_template_id))
    error_message = "The launch_template_id must be null or a valid launch template ID starting with 'lt-'."
  }
}

variable "launch_template_name" {
  type        = string
  description = "The name of an existing launch template to use. Required if launch_template_creation_enabled is false and launch_template_id is not provided."
  default     = null
}

variable "launch_template_version" {
  type        = string
  description = "The version of the launch template to use. Can be version number, '$Latest', or '$Default'."
  default     = "$Latest"
}

variable "launch_template" {
  type = object({
    description   = optional(string)
    image_id      = optional(string)
    instance_type = optional(string)
    key_name      = optional(string)
    user_data     = optional(string)
    ebs_optimized = optional(bool)
    kernel_id     = optional(string)
    ram_disk_id   = optional(string)

    # IAM Instance Profile - Only one of arn or name should be provided
    iam_instance_profile_arn  = optional(string)
    iam_instance_profile_name = optional(string)

    # Security Groups
    security_group_ids = optional(list(string), [])

    # Network Interfaces - When specified, security_group_ids should be empty as SGs are set per-interface
    network_interfaces = optional(list(object({
      device_index                = number
      description                 = optional(string)
      associate_public_ip_address = optional(bool)
      delete_on_termination       = optional(bool, true)
      security_groups             = optional(list(string), [])
      subnet_id                   = optional(string)
      private_ip_address          = optional(string)
      ipv4_address_count          = optional(number)
      ipv4_prefixes               = optional(list(string))
      ipv4_prefix_count           = optional(number)
      ipv6_addresses              = optional(list(string))
      ipv6_address_count          = optional(number)
      ipv6_prefixes               = optional(list(string))
      ipv6_prefix_count           = optional(number)
      network_interface_id        = optional(string)
      network_card_index          = optional(number)
      interface_type              = optional(string)
    })), [])

    # Block Device Mappings
    block_device_mappings = optional(list(object({
      device_name  = string
      no_device    = optional(string)
      virtual_name = optional(string)
      ebs = optional(object({
        volume_size           = optional(number)
        volume_type           = optional(string, "gp3")
        iops                  = optional(number)
        throughput            = optional(number)
        encrypted             = optional(bool, true)
        kms_key_id            = optional(string)
        delete_on_termination = optional(bool, true)
        snapshot_id           = optional(string)
      }))
    })), [])

    # Metadata Options (IMDSv2)
    metadata_options = optional(object({
      http_endpoint               = optional(string, "enabled")
      http_tokens                 = optional(string, "required")
      http_put_response_hop_limit = optional(number, 1)
      http_protocol_ipv6          = optional(string)
      instance_metadata_tags      = optional(string)
      }), {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    })

    # Monitoring
    monitoring_enabled = optional(bool, true)

    # Placement
    placement = optional(object({
      availability_zone       = optional(string)
      affinity                = optional(string)
      group_name              = optional(string)
      host_id                 = optional(string)
      host_resource_group_arn = optional(string)
      spread_domain           = optional(string)
      tenancy                 = optional(string)
      partition_number        = optional(number)
    }))

    # Instance Market Options (Spot)
    instance_market_options = optional(object({
      market_type = optional(string, "spot")
      spot_options = optional(object({
        block_duration_minutes         = optional(number)
        instance_interruption_behavior = optional(string, "terminate")
        max_price                      = optional(string)
        spot_instance_type             = optional(string, "one-time")
        valid_until                    = optional(string)
      }))
    }))

    # CPU Options
    cpu_options = optional(object({
      amd_sev_snp      = optional(string)
      core_count       = optional(number)
      threads_per_core = optional(number)
    }))

    # Credit Specification (T2/T3 instances)
    credit_specification = optional(object({
      cpu_credits = optional(string, "standard")
    }))

    # Capacity Reservation Specification
    capacity_reservation_specification = optional(object({
      capacity_reservation_preference = optional(string, "open")
      capacity_reservation_target = optional(object({
        capacity_reservation_id                 = optional(string)
        capacity_reservation_resource_group_arn = optional(string)
      }))
    }))

    # Enclave Options (AWS Nitro Enclaves)
    enclave_options = optional(object({
      enabled = optional(bool, false)
    }))

    # Hibernation Options
    hibernation_options = optional(object({
      configured = optional(bool, false)
    }))

    # License Specifications
    license_specifications = optional(list(object({
      license_configuration_arn = string
    })), [])

    # Maintenance Options
    maintenance_options = optional(object({
      auto_recovery = optional(string, "default")
    }))

    # Private DNS Name Options
    private_dns_name_options = optional(object({
      resource_name_dns_aaaa_record_enabled = optional(bool)
      resource_name_dns_a_record_enabled    = optional(bool)
      hostname_type                         = optional(string, "ip-name")
    }))

    # Instance Requirements (Attribute-based instance type selection) - Used with mixed instances policy
    instance_requirements = optional(object({
      vcpu_count = object({
        min = number
        max = optional(number)
      })
      memory_mib = object({
        min = number
        max = optional(number)
      })
      accelerator_count = optional(object({
        min = optional(number)
        max = optional(number)
      }))
      accelerator_manufacturers                               = optional(list(string))
      accelerator_names                                       = optional(list(string))
      accelerator_total_memory_mib                            = optional(object({ min = optional(number), max = optional(number) }))
      accelerator_types                                       = optional(list(string))
      allowed_instance_types                                  = optional(list(string))
      bare_metal                                              = optional(string)
      baseline_ebs_bandwidth_mbps                             = optional(object({ min = optional(number), max = optional(number) }))
      burstable_performance                                   = optional(string)
      cpu_manufacturers                                       = optional(list(string))
      excluded_instance_types                                 = optional(list(string))
      instance_generations                                    = optional(list(string))
      local_storage                                           = optional(string)
      local_storage_types                                     = optional(list(string))
      max_spot_price_as_percentage_of_optimal_on_demand_price = optional(number)
      memory_gib_per_vcpu                                     = optional(object({ min = optional(number), max = optional(number) }))
      network_bandwidth_gbps                                  = optional(object({ min = optional(number), max = optional(number) }))
      network_interface_count                                 = optional(object({ min = optional(number), max = optional(number) }))
      on_demand_max_price_percentage_over_lowest_price        = optional(number)
      require_hibernate_support                               = optional(bool)
      spot_max_price_percentage_over_lowest_price             = optional(number)
      total_local_storage_gb                                  = optional(object({ min = optional(number), max = optional(number) }))
    }))

    # Disable API Termination
    disable_api_termination = optional(bool)

    # Disable API Stop
    disable_api_stop = optional(bool)

    # Elastic GPU Specifications
    elastic_gpu_specifications = optional(list(object({
      type = string
    })), [])

    # Elastic Inference Accelerator
    elastic_inference_accelerator = optional(object({
      type = string
    }))

    # Tag Specifications for resources created by the launch template
    tag_specifications = optional(list(object({
      resource_type = string
      tags          = map(string)
    })), [])

    # Update Default Version
    update_default_version = optional(bool, true)
  })
  description = "Configuration for the launch template. Only used when launch_template_creation_enabled is true."
  default     = null
}

################################################################################
# Mixed Instances Policy
################################################################################

variable "mixed_instances_policy" {
  type = object({
    # Instances Distribution - Controls On-Demand vs Spot mix
    instances_distribution = optional(object({
      on_demand_allocation_strategy            = optional(string, "prioritized")
      on_demand_base_capacity                  = optional(number, 0)
      on_demand_percentage_above_base_capacity = optional(number, 100)
      spot_allocation_strategy                 = optional(string, "capacity-optimized")
      spot_instance_pools                      = optional(number)
      spot_max_price                           = optional(string)
    }))

    # Launch Template Overrides - Instance type variations
    launch_template_overrides = optional(list(object({
      instance_type     = optional(string)
      weighted_capacity = optional(number)

      # Launch Template Specification for this override
      launch_template_specification = optional(object({
        launch_template_id   = optional(string)
        launch_template_name = optional(string)
        version              = optional(string)
      }))

      # Instance Requirements for attribute-based instance type selection
      instance_requirements = optional(object({
        vcpu_count = object({
          min = number
          max = optional(number)
        })
        memory_mib = object({
          min = number
          max = optional(number)
        })
        accelerator_count = optional(object({
          min = optional(number)
          max = optional(number)
        }))
        accelerator_manufacturers                               = optional(list(string))
        accelerator_names                                       = optional(list(string))
        accelerator_total_memory_mib                            = optional(object({ min = optional(number), max = optional(number) }))
        accelerator_types                                       = optional(list(string))
        allowed_instance_types                                  = optional(list(string))
        bare_metal                                              = optional(string)
        baseline_ebs_bandwidth_mbps                             = optional(object({ min = optional(number), max = optional(number) }))
        burstable_performance                                   = optional(string)
        cpu_manufacturers                                       = optional(list(string))
        excluded_instance_types                                 = optional(list(string))
        instance_generations                                    = optional(list(string))
        local_storage                                           = optional(string)
        local_storage_types                                     = optional(list(string))
        max_spot_price_as_percentage_of_optimal_on_demand_price = optional(number)
        memory_gib_per_vcpu                                     = optional(object({ min = optional(number), max = optional(number) }))
        network_bandwidth_gbps                                  = optional(object({ min = optional(number), max = optional(number) }))
        network_interface_count                                 = optional(object({ min = optional(number), max = optional(number) }))
        on_demand_max_price_percentage_over_lowest_price        = optional(number)
        require_hibernate_support                               = optional(bool)
        spot_max_price_percentage_over_lowest_price             = optional(number)
        total_local_storage_gb                                  = optional(object({ min = optional(number), max = optional(number) }))
      }))
    })), [])
  })
  description = "Configuration for mixed instances policy to use a combination of On-Demand and Spot instances with multiple instance types."
  default     = null

  validation {
    condition = var.mixed_instances_policy == null || (
      var.mixed_instances_policy.instances_distribution == null ||
      contains(["prioritized", "lowest-price"], coalesce(var.mixed_instances_policy.instances_distribution.on_demand_allocation_strategy, "prioritized"))
    )
    error_message = "The on_demand_allocation_strategy must be 'prioritized' or 'lowest-price'."
  }

  validation {
    condition = var.mixed_instances_policy == null || (
      var.mixed_instances_policy.instances_distribution == null ||
      contains(["capacity-optimized", "capacity-optimized-prioritized", "lowest-price", "price-capacity-optimized"], coalesce(var.mixed_instances_policy.instances_distribution.spot_allocation_strategy, "capacity-optimized"))
    )
    error_message = "The spot_allocation_strategy must be 'capacity-optimized', 'capacity-optimized-prioritized', 'lowest-price', or 'price-capacity-optimized'."
  }

  validation {
    condition = var.mixed_instances_policy == null || (
      var.mixed_instances_policy.instances_distribution == null || (
        coalesce(var.mixed_instances_policy.instances_distribution.on_demand_percentage_above_base_capacity, 100) >= 0 &&
        coalesce(var.mixed_instances_policy.instances_distribution.on_demand_percentage_above_base_capacity, 100) <= 100
      )
    )
    error_message = "The on_demand_percentage_above_base_capacity must be between 0 and 100."
  }

  validation {
    condition = var.mixed_instances_policy == null || (
      var.mixed_instances_policy.instances_distribution == null ||
      coalesce(var.mixed_instances_policy.instances_distribution.on_demand_base_capacity, 0) >= 0
    )
    error_message = "The on_demand_base_capacity must be 0 or greater."
  }
}

################################################################################
# Instance Refresh
################################################################################

variable "instance_refresh" {
  type = object({
    # Strategy for instance refresh - currently only "Rolling" is supported
    strategy = optional(string, "Rolling")

    # Triggers that will cause an instance refresh
    triggers = optional(list(string), [])

    # Preferences for the instance refresh
    preferences = optional(object({
      # Checkpoint configuration for staged rollouts
      checkpoint_delay       = optional(number)
      checkpoint_percentages = optional(list(number))

      # Instance warmup time in seconds
      instance_warmup = optional(number)

      # Minimum percentage of healthy instances during refresh (0-100)
      min_healthy_percentage = optional(number, 90)

      # Maximum percentage of instances that can be healthy (100-200)
      # Values above 100 allow temporarily increasing capacity during refresh
      max_healthy_percentage = optional(number, 100)

      # Whether to skip replacing instances that already match the desired configuration
      skip_matching = optional(bool, false)

      # Whether to automatically rollback if the instance refresh fails
      auto_rollback = optional(bool, false)

      # How to handle scale-in protected instances: "Refresh", "Ignore", or "Wait"
      scale_in_protected_instances = optional(string, "Ignore")

      # How to handle instances in standby: "Terminate", "Ignore", or "Wait"
      standby_instances = optional(string, "Ignore")

      # Alarm specification for CloudWatch alarm-based rollback
      alarm_specification = optional(object({
        alarms = list(string)
      }))
    }))
  })
  description = "Configuration for instance refresh to perform rolling updates when the launch template or configuration changes."
  default     = null

  validation {
    condition = var.instance_refresh == null || (
      contains(["Rolling"], coalesce(var.instance_refresh.strategy, "Rolling"))
    )
    error_message = "The instance_refresh strategy must be 'Rolling'."
  }

  validation {
    condition = var.instance_refresh == null || var.instance_refresh.preferences == null || (
      coalesce(var.instance_refresh.preferences.min_healthy_percentage, 90) >= 0 &&
      coalesce(var.instance_refresh.preferences.min_healthy_percentage, 90) <= 100
    )
    error_message = "The min_healthy_percentage must be between 0 and 100."
  }

  validation {
    condition = var.instance_refresh == null || var.instance_refresh.preferences == null || (
      coalesce(var.instance_refresh.preferences.max_healthy_percentage, 100) >= 100 &&
      coalesce(var.instance_refresh.preferences.max_healthy_percentage, 100) <= 200
    )
    error_message = "The max_healthy_percentage must be between 100 and 200."
  }

  validation {
    condition = var.instance_refresh == null || var.instance_refresh.preferences == null || (
      contains(["Refresh", "Ignore", "Wait"], coalesce(var.instance_refresh.preferences.scale_in_protected_instances, "Ignore"))
    )
    error_message = "The scale_in_protected_instances must be 'Refresh', 'Ignore', or 'Wait'."
  }

  validation {
    condition = var.instance_refresh == null || var.instance_refresh.preferences == null || (
      contains(["Terminate", "Ignore", "Wait"], coalesce(var.instance_refresh.preferences.standby_instances, "Ignore"))
    )
    error_message = "The standby_instances must be 'Terminate', 'Ignore', or 'Wait'."
  }

  validation {
    condition = var.instance_refresh == null || var.instance_refresh.preferences == null || (
      var.instance_refresh.preferences.checkpoint_percentages == null ||
      alltrue([for p in var.instance_refresh.preferences.checkpoint_percentages : p >= 0 && p <= 100])
    )
    error_message = "All checkpoint_percentages must be between 0 and 100."
  }
}

################################################################################
# Warm Pool
################################################################################

variable "warm_pool" {
  type = object({
    # Pool state determines the state of instances in the warm pool
    # "Stopped" - Instances are stopped (default, cost-effective)
    # "Running" - Instances are running (fastest launch, higher cost)
    # "Hibernated" - Instances are hibernated (preserves memory state)
    pool_state = optional(string, "Stopped")

    # Minimum number of instances to maintain in the warm pool
    min_size = optional(number, 0)

    # Maximum number of instances that can be in the warm pool or in a pending state
    # If not specified, the warm pool has no max capacity limit
    max_group_prepared_capacity = optional(number)

    # Instance reuse policy configuration
    instance_reuse_policy = optional(object({
      # Whether to return instances to the warm pool on scale in
      reuse_on_scale_in = optional(bool, false)
    }))
  })
  description = "Configuration for warm pool to maintain pre-initialized instances for faster scaling."
  default     = null

  validation {
    condition = var.warm_pool == null || (
      contains(["Stopped", "Running", "Hibernated"], coalesce(var.warm_pool.pool_state, "Stopped"))
    )
    error_message = "The pool_state must be 'Stopped', 'Running', or 'Hibernated'."
  }

  validation {
    condition = var.warm_pool == null || (
      coalesce(var.warm_pool.min_size, 0) >= 0
    )
    error_message = "The warm_pool min_size must be 0 or greater."
  }

  validation {
    condition = var.warm_pool == null || (
      var.warm_pool.max_group_prepared_capacity == null ||
      var.warm_pool.max_group_prepared_capacity >= 0
    )
    error_message = "The max_group_prepared_capacity must be null or 0 or greater."
  }
}

################################################################################
# Lifecycle Hooks
################################################################################

variable "lifecycle_hooks" {
  type = list(object({
    # Name of the lifecycle hook (required)
    name = string

    # Lifecycle transition - when the hook is triggered (required)
    # "autoscaling:EC2_INSTANCE_LAUNCHING" - During instance launch
    # "autoscaling:EC2_INSTANCE_TERMINATING" - During instance termination
    lifecycle_transition = string

    # Default result when the heartbeat times out
    # "CONTINUE" - Proceed with the launch or termination
    # "ABANDON" - Stop the launch or termination (default)
    default_result = optional(string, "ABANDON")

    # Heartbeat timeout in seconds (default 3600, max 7200)
    # How long to wait for a heartbeat before timing out
    heartbeat_timeout = optional(number, 3600)

    # Additional metadata to send with the notification
    notification_metadata = optional(string)

    # ARN of the SNS topic or SQS queue to send notifications to
    notification_target_arn = optional(string)

    # IAM role ARN that allows the Auto Scaling Group to publish to the notification target
    role_arn = optional(string)
  }))
  description = "List of lifecycle hook configurations. Lifecycle hooks let you perform custom actions during instance launch or termination."
  default     = []

  validation {
    condition = alltrue([
      for hook in var.lifecycle_hooks :
      contains(["autoscaling:EC2_INSTANCE_LAUNCHING", "autoscaling:EC2_INSTANCE_TERMINATING"], hook.lifecycle_transition)
    ])
    error_message = "Each lifecycle_transition must be 'autoscaling:EC2_INSTANCE_LAUNCHING' or 'autoscaling:EC2_INSTANCE_TERMINATING'."
  }

  validation {
    condition = alltrue([
      for hook in var.lifecycle_hooks :
      contains(["CONTINUE", "ABANDON"], coalesce(hook.default_result, "ABANDON"))
    ])
    error_message = "Each default_result must be 'CONTINUE' or 'ABANDON'."
  }

  validation {
    condition = alltrue([
      for hook in var.lifecycle_hooks :
      coalesce(hook.heartbeat_timeout, 3600) >= 30 && coalesce(hook.heartbeat_timeout, 3600) <= 7200
    ])
    error_message = "Each heartbeat_timeout must be between 30 and 7200 seconds."
  }

  validation {
    condition = alltrue([
      for hook in var.lifecycle_hooks :
      hook.notification_target_arn == null || can(regex("^arn:aws:(sns|sqs):", hook.notification_target_arn))
    ])
    error_message = "Each notification_target_arn must be null or a valid SNS topic or SQS queue ARN."
  }

  validation {
    condition = alltrue([
      for hook in var.lifecycle_hooks :
      hook.role_arn == null || can(regex("^arn:aws:iam::", hook.role_arn))
    ])
    error_message = "Each role_arn must be null or a valid IAM role ARN."
  }
}

################################################################################
# Scaling Policies
################################################################################

variable "scaling_policies" {
  type = list(object({
    # Name of the scaling policy (required)
    name = string

    # Type of scaling policy (required)
    # "SimpleScaling" - Scale based on a single adjustment
    # "StepScaling" - Scale based on step adjustments
    # "TargetTrackingScaling" - Scale to maintain a target metric value
    # "PredictiveScaling" - Use ML to predict and scale proactively
    policy_type = string

    # Estimated time in seconds for new instances to warm up (all policy types except SimpleScaling)
    estimated_instance_warmup = optional(number)

    # Whether the scaling policy is enabled (default true)
    enabled = optional(bool, true)

    ############################################################################
    # SimpleScaling and StepScaling Configuration
    ############################################################################

    # Adjustment type - how scaling_adjustment is interpreted
    # "ChangeInCapacity" - Add/remove exact number of instances
    # "ExactCapacity" - Set capacity to exact number
    # "PercentChangeInCapacity" - Add/remove percentage of current capacity
    adjustment_type = optional(string)

    # Minimum adjustment for PercentChangeInCapacity type
    min_adjustment_magnitude = optional(number)

    # Cooldown in seconds (SimpleScaling only)
    cooldown = optional(number)

    # Number of instances to adjust (SimpleScaling only)
    scaling_adjustment = optional(number)

    # Aggregation type for metrics (StepScaling only): "Minimum", "Maximum", or "Average"
    metric_aggregation_type = optional(string)

    # Step adjustments for StepScaling policy
    step_adjustments = optional(list(object({
      # Lower bound of the metric range (null = negative infinity)
      metric_interval_lower_bound = optional(number)
      # Upper bound of the metric range (null = positive infinity)
      metric_interval_upper_bound = optional(number)
      # Number of instances to adjust
      scaling_adjustment = number
    })))

    ############################################################################
    # TargetTrackingScaling Configuration
    ############################################################################

    target_tracking_configuration = optional(object({
      # Target value for the metric
      target_value = number

      # Whether target tracking can scale in automatically
      scale_in_enabled = optional(bool, true)

      # Predefined metric specification - use one of AWS's built-in metrics
      predefined_metric_specification = optional(object({
        # Predefined metric type:
        # "ASGAverageCPUUtilization" - Average CPU utilization
        # "ASGAverageNetworkIn" - Average bytes received
        # "ASGAverageNetworkOut" - Average bytes sent
        # "ALBRequestCountPerTarget" - Request count per target
        predefined_metric_type = string
        # Resource label (required for ALBRequestCountPerTarget)
        resource_label = optional(string)
      }))

      # Customized metric specification - define your own metric
      customized_metric_specification = optional(object({
        # Single metric (simple case)
        metric_name = optional(string)
        namespace   = optional(string)
        statistic   = optional(string)
        unit        = optional(string)
        dimensions = optional(list(object({
          name  = string
          value = string
        })))

        # Multiple metrics with math expression (advanced case)
        metrics = optional(list(object({
          # Unique identifier for this metric
          id = string
          # Whether this metric is returned (one metric must have return_data = true)
          return_data = optional(bool)
          # Label for the metric
          label = optional(string)
          # Math expression using other metric IDs
          expression = optional(string)

          # Metric stat for CloudWatch metrics
          metric_stat = optional(object({
            metric = object({
              metric_name = string
              namespace   = string
              dimensions = optional(list(object({
                name  = string
                value = string
              })))
            })
            stat = string
            unit = optional(string)
          }))
        })))
      }))
    }))

    ############################################################################
    # PredictiveScaling Configuration
    ############################################################################

    predictive_scaling_configuration = optional(object({
      # Sizing mode: "ForecastAndScale" or "ForecastOnly"
      mode = optional(string, "ForecastOnly")

      # Buffer time in seconds (how far ahead to scale, 0-3600)
      scheduling_buffer_time = optional(number)

      # Max capacity breach behavior: "IncreaseMaxCapacity" or "HonorMaxCapacity"
      max_capacity_breach_behavior = optional(string, "HonorMaxCapacity")

      # Maximum capacity buffer (percentage above forecast, 0-100)
      max_capacity_buffer = optional(number)

      # Metric specifications (at least one required)
      metric_specifications = list(object({
        # Target value for scaling
        target_value = number

        # Predefined load metric (e.g., ASGTotalCPUUtilization)
        predefined_load_metric_specification = optional(object({
          predefined_metric_type = string
          resource_label         = optional(string)
        }))

        # Predefined scaling metric
        predefined_scaling_metric_specification = optional(object({
          predefined_metric_type = string
          resource_label         = optional(string)
        }))

        # Predefined metric pair (load + scaling together)
        predefined_metric_pair_specification = optional(object({
          predefined_metric_type = string
          resource_label         = optional(string)
        }))

        # Customized load metric
        customized_load_metric_specification = optional(object({
          metric_data_queries = list(object({
            id          = string
            expression  = optional(string)
            label       = optional(string)
            return_data = optional(bool)
            metric_stat = optional(object({
              metric = object({
                metric_name = string
                namespace   = string
                dimensions = optional(list(object({
                  name  = string
                  value = string
                })))
              })
              stat = string
              unit = optional(string)
            }))
          }))
        }))

        # Customized scaling metric
        customized_scaling_metric_specification = optional(object({
          metric_data_queries = list(object({
            id          = string
            expression  = optional(string)
            label       = optional(string)
            return_data = optional(bool)
            metric_stat = optional(object({
              metric = object({
                metric_name = string
                namespace   = string
                dimensions = optional(list(object({
                  name  = string
                  value = string
                })))
              })
              stat = string
              unit = optional(string)
            }))
          }))
        }))

        # Customized capacity metric
        customized_capacity_metric_specification = optional(object({
          metric_data_queries = list(object({
            id          = string
            expression  = optional(string)
            label       = optional(string)
            return_data = optional(bool)
            metric_stat = optional(object({
              metric = object({
                metric_name = string
                namespace   = string
                dimensions = optional(list(object({
                  name  = string
                  value = string
                })))
              })
              stat = string
              unit = optional(string)
            }))
          }))
        }))
      }))
    }))
  }))
  description = "List of scaling policy configurations. Supports SimpleScaling, StepScaling, TargetTrackingScaling, and PredictiveScaling policy types."
  default     = []

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      contains(["SimpleScaling", "StepScaling", "TargetTrackingScaling", "PredictiveScaling"], policy.policy_type)
    ])
    error_message = "Each policy_type must be 'SimpleScaling', 'StepScaling', 'TargetTrackingScaling', or 'PredictiveScaling'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.adjustment_type == null || contains(["ChangeInCapacity", "ExactCapacity", "PercentChangeInCapacity"], policy.adjustment_type)
    ])
    error_message = "Each adjustment_type must be 'ChangeInCapacity', 'ExactCapacity', or 'PercentChangeInCapacity'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.metric_aggregation_type == null || contains(["Minimum", "Maximum", "Average"], policy.metric_aggregation_type)
    ])
    error_message = "Each metric_aggregation_type must be 'Minimum', 'Maximum', or 'Average'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.target_tracking_configuration == null ||
      policy.target_tracking_configuration.predefined_metric_specification == null ||
      contains(
        ["ASGAverageCPUUtilization", "ASGAverageNetworkIn", "ASGAverageNetworkOut", "ALBRequestCountPerTarget"],
        policy.target_tracking_configuration.predefined_metric_specification.predefined_metric_type
      )
    ])
    error_message = "Each predefined_metric_type for target tracking must be 'ASGAverageCPUUtilization', 'ASGAverageNetworkIn', 'ASGAverageNetworkOut', or 'ALBRequestCountPerTarget'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.predictive_scaling_configuration == null ||
      contains(["ForecastAndScale", "ForecastOnly"], coalesce(policy.predictive_scaling_configuration.mode, "ForecastOnly"))
    ])
    error_message = "Each predictive scaling mode must be 'ForecastAndScale' or 'ForecastOnly'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.predictive_scaling_configuration == null ||
      contains(["IncreaseMaxCapacity", "HonorMaxCapacity"], coalesce(policy.predictive_scaling_configuration.max_capacity_breach_behavior, "HonorMaxCapacity"))
    ])
    error_message = "Each max_capacity_breach_behavior must be 'IncreaseMaxCapacity' or 'HonorMaxCapacity'."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.predictive_scaling_configuration == null ||
      policy.predictive_scaling_configuration.scheduling_buffer_time == null ||
      (policy.predictive_scaling_configuration.scheduling_buffer_time >= 0 && policy.predictive_scaling_configuration.scheduling_buffer_time <= 3600)
    ])
    error_message = "Each scheduling_buffer_time must be between 0 and 3600 seconds."
  }

  validation {
    condition = alltrue([
      for policy in var.scaling_policies :
      policy.predictive_scaling_configuration == null ||
      policy.predictive_scaling_configuration.max_capacity_buffer == null ||
      (policy.predictive_scaling_configuration.max_capacity_buffer >= 0 && policy.predictive_scaling_configuration.max_capacity_buffer <= 100)
    ])
    error_message = "Each max_capacity_buffer must be between 0 and 100."
  }
}

################################################################################
# Notifications
################################################################################

variable "notifications" {
  type = object({
    # ARN of the SNS topic to send notifications to (required)
    topic_arn = string

    # List of notification types to send (optional, defaults to all)
    # Valid values:
    # - "autoscaling:EC2_INSTANCE_LAUNCH" - Instance launched
    # - "autoscaling:EC2_INSTANCE_LAUNCH_ERROR" - Instance launch failed
    # - "autoscaling:EC2_INSTANCE_TERMINATE" - Instance terminated
    # - "autoscaling:EC2_INSTANCE_TERMINATE_ERROR" - Instance termination failed
    # - "autoscaling:TEST_NOTIFICATION" - Test notification
    notifications = optional(list(string), [
      "autoscaling:EC2_INSTANCE_LAUNCH",
      "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
      "autoscaling:EC2_INSTANCE_TERMINATE",
      "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
    ])
  })
  description = "Configuration for SNS notifications when Auto Scaling events occur."
  default     = null

  validation {
    condition = var.notifications == null || (
      can(regex("^arn:aws:sns:", var.notifications.topic_arn))
    )
    error_message = "The topic_arn must be a valid SNS topic ARN starting with 'arn:aws:sns:'."
  }

  validation {
    condition = var.notifications == null || (
      alltrue([
        for notification in coalesce(var.notifications.notifications, []) :
        contains([
          "autoscaling:EC2_INSTANCE_LAUNCH",
          "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
          "autoscaling:EC2_INSTANCE_TERMINATE",
          "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
          "autoscaling:TEST_NOTIFICATION"
        ], notification)
      ])
    )
    error_message = "Each notification must be one of: 'autoscaling:EC2_INSTANCE_LAUNCH', 'autoscaling:EC2_INSTANCE_LAUNCH_ERROR', 'autoscaling:EC2_INSTANCE_TERMINATE', 'autoscaling:EC2_INSTANCE_TERMINATE_ERROR', 'autoscaling:TEST_NOTIFICATION'."
  }
}

################################################################################
# Traffic Sources
################################################################################

variable "traffic_sources" {
  type = list(object({
    # Identifier for the traffic source (required)
    # For elbv2: Target group ARN
    # For vpc-lattice: VPC Lattice target group ARN
    identifier = string

    # Type of traffic source (required)
    # "elbv2" - Elastic Load Balancing v2 target group
    # "vpc-lattice" - VPC Lattice target group
    type = string
  }))
  description = "List of traffic source attachments for the Auto Scaling Group. Supports ELBv2 and VPC Lattice target groups."
  default     = []

  validation {
    condition = alltrue([
      for ts in var.traffic_sources :
      contains(["elbv2", "vpc-lattice"], ts.type)
    ])
    error_message = "Each traffic source type must be 'elbv2' or 'vpc-lattice'."
  }

  validation {
    condition = alltrue([
      for ts in var.traffic_sources :
      ts.type != "elbv2" || can(regex("^arn:aws:elasticloadbalancing:", ts.identifier))
    ])
    error_message = "Traffic sources with type 'elbv2' must have an identifier that is a valid ELBv2 ARN starting with 'arn:aws:elasticloadbalancing:'."
  }

  validation {
    condition = alltrue([
      for ts in var.traffic_sources :
      ts.type != "vpc-lattice" || can(regex("^arn:aws:vpc-lattice:", ts.identifier))
    ])
    error_message = "Traffic sources with type 'vpc-lattice' must have an identifier that is a valid VPC Lattice ARN starting with 'arn:aws:vpc-lattice:'."
  }
}

################################################################################
# Scheduled Actions
################################################################################

variable "schedules" {
  type = list(object({
    # Name of the scheduled action (required)
    name = string

    # Minimum size for the scheduled action (optional)
    min_size = optional(number)

    # Maximum size for the scheduled action (optional)
    max_size = optional(number)

    # Desired capacity for the scheduled action (optional)
    desired_capacity = optional(number)

    # Start time for the scheduled action in ISO 8601 format (optional)
    # Example: "2024-01-15T10:00:00Z"
    start_time = optional(string)

    # End time for the scheduled action in ISO 8601 format (optional)
    # Example: "2024-12-31T23:59:59Z"
    end_time = optional(string)

    # Recurrence schedule in cron format (optional)
    # Example: "0 9 * * MON-FRI" (9 AM on weekdays)
    recurrence = optional(string)

    # Time zone for the cron expression (optional)
    # Example: "America/New_York", "UTC"
    time_zone = optional(string)
  }))
  description = "List of scheduled scaling actions. Schedules can be recurring (cron) or one-time."
  default     = []

  validation {
    condition = alltrue([
      for schedule in var.schedules :
      length(schedule.name) > 0
    ])
    error_message = "Each schedule must have a non-empty name."
  }

  validation {
    condition = alltrue([
      for schedule in var.schedules :
      schedule.min_size == null || schedule.min_size >= 0
    ])
    error_message = "Each schedule min_size must be null or 0 or greater."
  }

  validation {
    condition = alltrue([
      for schedule in var.schedules :
      schedule.max_size == null || schedule.max_size >= 1
    ])
    error_message = "Each schedule max_size must be null or at least 1."
  }

  validation {
    condition = alltrue([
      for schedule in var.schedules :
      schedule.desired_capacity == null || schedule.desired_capacity >= 0
    ])
    error_message = "Each schedule desired_capacity must be null or 0 or greater."
  }
}

################################################################################
# Instance Maintenance Policy
################################################################################

variable "instance_maintenance_policy" {
  type = object({
    # Minimum percentage of healthy instances during replacement (0-100)
    # Lower values allow faster replacements but reduce capacity
    min_healthy_percentage = optional(number, 90)

    # Maximum percentage of instances allowed during replacement (100-200)
    # Values above 100 allow temporarily increasing capacity during replacement
    max_healthy_percentage = optional(number, 120)
  })
  description = "Configuration for instance maintenance policy controlling the minimum and maximum capacity during instance replacement operations."
  default     = null

  validation {
    condition = var.instance_maintenance_policy == null || (
      coalesce(var.instance_maintenance_policy.min_healthy_percentage, 90) >= 0 &&
      coalesce(var.instance_maintenance_policy.min_healthy_percentage, 90) <= 100
    )
    error_message = "The min_healthy_percentage must be between 0 and 100."
  }

  validation {
    condition = var.instance_maintenance_policy == null || (
      coalesce(var.instance_maintenance_policy.max_healthy_percentage, 120) >= 100 &&
      coalesce(var.instance_maintenance_policy.max_healthy_percentage, 120) <= 200
    )
    error_message = "The max_healthy_percentage must be between 100 and 200."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
