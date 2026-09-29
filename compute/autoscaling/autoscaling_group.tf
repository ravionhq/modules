################################################################################
# Auto Scaling Group
################################################################################

resource "aws_autoscaling_group" "this" {
  name        = var.name_prefix == null ? var.name : null
  name_prefix = var.name_prefix

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  vpc_zone_identifier = var.vpc_zone_identifier

  # Timing and cooldown
  default_cooldown        = var.default_cooldown
  default_instance_warmup = var.default_instance_warmup

  # Instance protection and lifecycle
  protect_from_scale_in = var.scale_in_protection_enabled
  max_instance_lifetime = var.max_instance_lifetime
  force_delete          = var.force_delete_enabled

  # Health checks
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Capacity and scaling behavior
  capacity_rebalance   = var.capacity_rebalance_enabled
  termination_policies = var.termination_policies
  suspended_processes  = var.suspended_processes

  # CloudWatch metrics
  enabled_metrics     = var.enabled_metrics
  metrics_granularity = length(var.enabled_metrics) > 0 ? var.metrics_granularity : null

  # Service-linked role
  service_linked_role_arn = var.service_linked_role_arn

  # Load balancer integration
  target_group_arns = var.target_group_arns

  # Wait settings
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  ################################################################################
  # Launch Template (when not using mixed instances policy)
  ################################################################################

  dynamic "launch_template" {
    for_each = local.enable_mixed_instances_policy ? [] : [1]
    content {
      id      = local.create_launch_template ? aws_launch_template.this[0].id : var.launch_template_id
      name    = local.create_launch_template ? null : (var.launch_template_id == null ? var.launch_template_name : null)
      version = var.launch_template_version
    }
  }

  ################################################################################
  # Mixed Instances Policy (for Spot/On-Demand mix)
  ################################################################################

  dynamic "mixed_instances_policy" {
    for_each = local.enable_mixed_instances_policy ? [var.mixed_instances_policy] : []
    content {
      # Instances distribution
      dynamic "instances_distribution" {
        for_each = mixed_instances_policy.value.instances_distribution != null ? [mixed_instances_policy.value.instances_distribution] : []
        content {
          on_demand_allocation_strategy            = instances_distribution.value.on_demand_allocation_strategy
          on_demand_base_capacity                  = instances_distribution.value.on_demand_base_capacity
          on_demand_percentage_above_base_capacity = instances_distribution.value.on_demand_percentage_above_base_capacity
          spot_allocation_strategy                 = instances_distribution.value.spot_allocation_strategy
          spot_instance_pools                      = instances_distribution.value.spot_instance_pools
          spot_max_price                           = instances_distribution.value.spot_max_price
        }
      }

      # Launch template specification
      launch_template {
        launch_template_specification {
          launch_template_id   = local.create_launch_template ? aws_launch_template.this[0].id : var.launch_template_id
          launch_template_name = local.create_launch_template ? null : (var.launch_template_id == null ? var.launch_template_name : null)
          version              = var.launch_template_version
        }

        # Launch template overrides for instance type diversification
        dynamic "override" {
          for_each = coalesce(mixed_instances_policy.value.launch_template_overrides, [])
          content {
            instance_type     = override.value.instance_type
            weighted_capacity = override.value.weighted_capacity

            # Override launch template specification
            dynamic "launch_template_specification" {
              for_each = override.value.launch_template_specification != null ? [override.value.launch_template_specification] : []
              content {
                launch_template_id   = launch_template_specification.value.launch_template_id
                launch_template_name = launch_template_specification.value.launch_template_name
                version              = launch_template_specification.value.version
              }
            }

            # Instance requirements for attribute-based instance type selection
            dynamic "instance_requirements" {
              for_each = override.value.instance_requirements != null ? [override.value.instance_requirements] : []
              content {
                vcpu_count {
                  min = instance_requirements.value.vcpu_count.min
                  max = instance_requirements.value.vcpu_count.max
                }

                memory_mib {
                  min = instance_requirements.value.memory_mib.min
                  max = instance_requirements.value.memory_mib.max
                }

                dynamic "accelerator_count" {
                  for_each = instance_requirements.value.accelerator_count != null ? [instance_requirements.value.accelerator_count] : []
                  content {
                    min = accelerator_count.value.min
                    max = accelerator_count.value.max
                  }
                }

                accelerator_manufacturers = instance_requirements.value.accelerator_manufacturers
                accelerator_names         = instance_requirements.value.accelerator_names

                dynamic "accelerator_total_memory_mib" {
                  for_each = instance_requirements.value.accelerator_total_memory_mib != null ? [instance_requirements.value.accelerator_total_memory_mib] : []
                  content {
                    min = accelerator_total_memory_mib.value.min
                    max = accelerator_total_memory_mib.value.max
                  }
                }

                accelerator_types      = instance_requirements.value.accelerator_types
                allowed_instance_types = instance_requirements.value.allowed_instance_types
                bare_metal             = instance_requirements.value.bare_metal

                dynamic "baseline_ebs_bandwidth_mbps" {
                  for_each = instance_requirements.value.baseline_ebs_bandwidth_mbps != null ? [instance_requirements.value.baseline_ebs_bandwidth_mbps] : []
                  content {
                    min = baseline_ebs_bandwidth_mbps.value.min
                    max = baseline_ebs_bandwidth_mbps.value.max
                  }
                }

                burstable_performance   = instance_requirements.value.burstable_performance
                cpu_manufacturers       = instance_requirements.value.cpu_manufacturers
                excluded_instance_types = instance_requirements.value.excluded_instance_types
                instance_generations    = instance_requirements.value.instance_generations
                local_storage           = instance_requirements.value.local_storage
                local_storage_types     = instance_requirements.value.local_storage_types

                max_spot_price_as_percentage_of_optimal_on_demand_price = instance_requirements.value.max_spot_price_as_percentage_of_optimal_on_demand_price

                dynamic "memory_gib_per_vcpu" {
                  for_each = instance_requirements.value.memory_gib_per_vcpu != null ? [instance_requirements.value.memory_gib_per_vcpu] : []
                  content {
                    min = memory_gib_per_vcpu.value.min
                    max = memory_gib_per_vcpu.value.max
                  }
                }

                dynamic "network_bandwidth_gbps" {
                  for_each = instance_requirements.value.network_bandwidth_gbps != null ? [instance_requirements.value.network_bandwidth_gbps] : []
                  content {
                    min = network_bandwidth_gbps.value.min
                    max = network_bandwidth_gbps.value.max
                  }
                }

                dynamic "network_interface_count" {
                  for_each = instance_requirements.value.network_interface_count != null ? [instance_requirements.value.network_interface_count] : []
                  content {
                    min = network_interface_count.value.min
                    max = network_interface_count.value.max
                  }
                }

                on_demand_max_price_percentage_over_lowest_price = instance_requirements.value.on_demand_max_price_percentage_over_lowest_price
                require_hibernate_support                        = instance_requirements.value.require_hibernate_support
                spot_max_price_percentage_over_lowest_price      = instance_requirements.value.spot_max_price_percentage_over_lowest_price

                dynamic "total_local_storage_gb" {
                  for_each = instance_requirements.value.total_local_storage_gb != null ? [instance_requirements.value.total_local_storage_gb] : []
                  content {
                    min = total_local_storage_gb.value.min
                    max = total_local_storage_gb.value.max
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  ################################################################################
  # Instance Refresh
  ################################################################################

  dynamic "instance_refresh" {
    for_each = local.enable_instance_refresh ? [var.instance_refresh] : []
    content {
      strategy = instance_refresh.value.strategy
      triggers = instance_refresh.value.triggers

      dynamic "preferences" {
        for_each = instance_refresh.value.preferences != null ? [instance_refresh.value.preferences] : []
        content {
          checkpoint_delay       = preferences.value.checkpoint_delay
          checkpoint_percentages = preferences.value.checkpoint_percentages
          instance_warmup        = preferences.value.instance_warmup
          min_healthy_percentage = preferences.value.min_healthy_percentage
          max_healthy_percentage = preferences.value.max_healthy_percentage
          skip_matching          = preferences.value.skip_matching
          auto_rollback          = preferences.value.auto_rollback

          scale_in_protected_instances = preferences.value.scale_in_protected_instances
          standby_instances            = preferences.value.standby_instances

          dynamic "alarm_specification" {
            for_each = preferences.value.alarm_specification != null ? [preferences.value.alarm_specification] : []
            content {
              alarms = alarm_specification.value.alarms
            }
          }
        }
      }
    }
  }

  ################################################################################
  # Instance Maintenance Policy
  ################################################################################

  dynamic "instance_maintenance_policy" {
    for_each = local.enable_instance_maintenance_policy ? [var.instance_maintenance_policy] : []
    content {
      min_healthy_percentage = instance_maintenance_policy.value.min_healthy_percentage
      max_healthy_percentage = instance_maintenance_policy.value.max_healthy_percentage
    }
  }

  ################################################################################
  # Warm Pool
  ################################################################################

  dynamic "warm_pool" {
    for_each = local.enable_warm_pool ? [var.warm_pool] : []
    content {
      # Pool state determines the state of instances in the warm pool
      pool_state = warm_pool.value.pool_state

      # Minimum number of instances to maintain in the warm pool
      min_size = warm_pool.value.min_size

      # Maximum number of instances that can be in the warm pool or in a pending state
      max_group_prepared_capacity = warm_pool.value.max_group_prepared_capacity

      # Instance reuse policy configuration
      dynamic "instance_reuse_policy" {
        for_each = warm_pool.value.instance_reuse_policy != null ? [warm_pool.value.instance_reuse_policy] : []
        content {
          reuse_on_scale_in = instance_reuse_policy.value.reuse_on_scale_in
        }
      }
    }
  }

  ################################################################################
  # Tags
  ################################################################################

  dynamic "tag" {
    for_each = local.asg_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = var.tag_propagation_at_launch_enabled
    }
  }

  ################################################################################
  # Lifecycle
  ################################################################################

  # Note: desired_capacity is always ignored to support external scaling mechanisms
  # (ECS capacity providers, scaling policies, scheduled actions). The initial
  # desired_capacity is set on creation, but subsequent changes made outside
  # Terraform won't cause drift. To change desired_capacity via Terraform,
  # use a scaling policy or update min_size.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}
