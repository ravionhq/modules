# Auto Scaling Group Module

This module creates an AWS Auto Scaling Group with optional launch template, scaling policies, lifecycle hooks, scheduled actions, warm pool, and traffic source integrations.

By default the group uses the fixed `name`. For workloads that need create-before-destroy replacements (including recovery from a tainted group), set `name_prefix` to generate a unique physical group name. Use `autoscaling_group_name` wherever a consumer needs that physical name; `name` remains the stable prefix for resource tags and other companion resources. Switching an existing fixed-name group to prefix mode replaces the group and its instances, so back up any instance-local data first.

## Features

- Auto Scaling Group with configurable capacity limits and health checks
- Optional launch template creation with full configuration support
- Mixed instances policy for Spot and On-Demand instances
- Warm pool for pre-initialized instances and faster scaling
- Multiple scaling policy types: Simple, Step, Target Tracking, and Predictive
- Lifecycle hooks for custom actions during instance launch/termination
- Scheduled scaling actions with cron support
- Instance refresh for rolling updates
- Traffic source attachments (ELBv2 and VPC Lattice)
- SNS notifications for Auto Scaling events
- ECS capacity provider integration support
- IMDSv2 enforcement by default for enhanced security

## Usage

### Basic Auto Scaling Group

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size         = 1
  max_size         = 10
  desired_capacity = 2

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }
}
```

### With Mixed Instances Policy (Spot)

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size         = 2
  max_size         = 20
  desired_capacity = 4

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  # Use Spot instances with On-Demand base capacity
  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }
    launch_template_overrides = [
      { instance_type = "t3.medium" },
      { instance_type = "t3.large" },
      { instance_type = "t3a.medium" },
      { instance_type = "t3a.large" }
    ]
  }

  # Enable capacity rebalancing for Spot
  capacity_rebalance_enabled = true
}
```

### With Target Tracking Scaling

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 2
  max_size = 50

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  scaling_policies = [
    {
      name        = "cpu-target-tracking"
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        target_value = 70.0
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    }
  ]
}
```

### With Warm Pool

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 2
  max_size = 20

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  # Pre-warm instances for faster scaling
  warm_pool = {
    pool_state                  = "Stopped"
    min_size                    = 2
    max_group_prepared_capacity = 5
    instance_reuse_policy = {
      reuse_on_scale_in = true
    }
  }
}
```

### With Scheduled Scaling

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 1
  max_size = 20

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  schedules = [
    {
      name             = "scale-up-morning"
      min_size         = 5
      max_size         = 20
      desired_capacity = 10
      recurrence       = "0 9 * * MON-FRI"
      time_zone        = "America/New_York"
    },
    {
      name             = "scale-down-evening"
      min_size         = 1
      max_size         = 5
      desired_capacity = 1
      recurrence       = "0 18 * * MON-FRI"
      time_zone        = "America/New_York"
    }
  ]
}
```

### With Lifecycle Hooks

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 2
  max_size = 10

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  lifecycle_hooks = [
    {
      name                 = "launch-hook"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 300
      notification_target_arn = "arn:aws:sns:us-east-1:123456789012:my-topic"
      role_arn                = "arn:aws:iam::123456789012:role/my-role"
    },
    {
      name                 = "terminate-hook"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 600
    }
  ]
}
```

### For ECS Capacity Provider

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "ecs-asg"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 0
  max_size = 10

  # Mark as ECS managed for capacity provider
  ecs_managed_tag_enabled          = true
  scale_in_protection_enabled = true

  launch_template = {
    image_id      = data.aws_ssm_parameter.ecs_ami.value
    instance_type = "t3.medium"
    user_data     = base64encode(templatefile("user_data.sh", { cluster_name = "my-cluster" }))
    iam_instance_profile_name = "ecsInstanceRole"
  }
}

# Use the output to create an ECS capacity provider
resource "aws_ecs_capacity_provider" "this" {
  name = "my-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = module.asg.autoscaling_group_arn
    managed_scaling {
      status          = module.asg.ecs_capacity_provider_config.managed_scaling_status
      target_capacity = 100
    }
    managed_termination_protection = module.asg.ecs_capacity_provider_config.managed_termination_protection
  }
}
```

### With Instance Refresh

```hcl
module "asg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/autoscaling?ref=v1.0.0"

  name                = "my-app"
  vpc_zone_identifier = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  min_size = 3
  max_size = 10

  launch_template = {
    image_id      = "ami-0123456789abcdef0"
    instance_type = "t3.medium"
  }

  # Automatically refresh instances when launch template changes
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 90
      max_healthy_percentage = 110
      instance_warmup        = 300
      skip_matching          = true
      auto_rollback          = true
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources | `string` | n/a | yes |
| name_prefix | Optional prefix for a generated ASG name (enables create-before-destroy replacements) | `string` | `null` | no |
| tags | Map of tags to assign to resources | `map(string)` | `{}` | no |
| vpc_zone_identifier | List of subnet IDs for the ASG | `list(string)` | n/a | yes |

### Auto Scaling Group - Core

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| min_size | Minimum number of instances | `number` | `0` | no |
| max_size | Maximum number of instances | `number` | `10` | no |
| desired_capacity | Desired number of instances (null defaults to min_size) | `number` | `null` | no |
| default_cooldown | Cooldown period in seconds | `number` | `300` | no |
| default_instance_warmup | Instance warmup time in seconds | `number` | `null` | no |
| wait_for_capacity_timeout | Timeout for waiting for capacity | `string` | `"10m"` | no |

### Auto Scaling Group - Instance Protection

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| scale_in_protection_enabled | Protect instances from scale in | `bool` | `false` | no |
| max_instance_lifetime | Maximum instance lifetime in seconds (0 or 86400-31536000) | `number` | `null` | no |
| force_delete_enabled | Force delete without waiting for instances | `bool` | `false` | no |
| ignore_desired_capacity_changes | Ignore desired capacity changes | `bool` | `false` | no |

### Auto Scaling Group - Health Checks

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| health_check_type | Health check type: EC2 or ELB | `string` | `"EC2"` | no |
| health_check_grace_period | Health check grace period in seconds | `number` | `300` | no |

### Auto Scaling Group - Scaling Behavior

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| capacity_rebalance_enabled | Enable Spot capacity rebalancing | `bool` | `false` | no |
| termination_policies | List of termination policies | `list(string)` | `["Default"]` | no |
| suspended_processes | List of processes to suspend | `list(string)` | `[]` | no |

### Auto Scaling Group - Metrics

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enabled_metrics | List of CloudWatch metrics to enable | `list(string)` | `[]` | no |
| metrics_granularity | Metrics granularity (only 1Minute supported) | `string` | `"1Minute"` | no |

### Auto Scaling Group - Integrations

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| service_linked_role_arn | Custom service-linked role ARN | `string` | `null` | no |
| target_group_arns | List of target group ARNs | `list(string)` | `[]` | no |
| ecs_managed_tag_enabled | Add AmazonECSManaged tag for ECS integration | `bool` | `false` | no |
| tag_propagation_at_launch_enabled | Propagate tags to launched instances | `bool` | `true` | no |

### Launch Template

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| launch_template_creation_enabled | Whether to create a launch template | `bool` | `true` | no |
| launch_template_id | Existing launch template ID | `string` | `null` | no |
| launch_template_name | Existing launch template name | `string` | `null` | no |
| launch_template_version | Launch template version | `string` | `"$Latest"` | no |
| launch_template | Launch template configuration object | `object` | `null` | no |

### Mixed Instances Policy

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| mixed_instances_policy | Mixed instances policy configuration for Spot/On-Demand | `object` | `null` | no |

### Instance Refresh

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| instance_refresh | Instance refresh configuration for rolling updates | `object` | `null` | no |

### Warm Pool

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| warm_pool | Warm pool configuration for pre-initialized instances | `object` | `null` | no |

### Lifecycle Hooks

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| lifecycle_hooks | List of lifecycle hook configurations | `list(object)` | `[]` | no |

### Scaling Policies

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| scaling_policies | List of scaling policy configurations | `list(object)` | `[]` | no |

### Notifications

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| notifications | SNS notification configuration | `object` | `null` | no |

### Traffic Sources

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| traffic_sources | List of traffic source attachments (ELBv2, VPC Lattice) | `list(object)` | `[]` | no |

### Scheduled Actions

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| schedules | List of scheduled scaling actions | `list(object)` | `[]` | no |

### Instance Maintenance Policy

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| instance_maintenance_policy | Instance maintenance policy configuration | `object` | `null` | no |

## Outputs

### Auto Scaling Group

| Name | Description |
|------|-------------|
| autoscaling_group_id | The ID of the Auto Scaling Group |
| autoscaling_group_arn | The ARN of the Auto Scaling Group |
| autoscaling_group_name | The name of the Auto Scaling Group |
| autoscaling_group_availability_zones | The availability zones of the ASG |
| autoscaling_group_vpc_zone_identifier | The subnet IDs of the ASG |
| autoscaling_group_min_size | Minimum size of the ASG |
| autoscaling_group_max_size | Maximum size of the ASG |
| autoscaling_group_desired_capacity | Desired capacity of the ASG |
| autoscaling_group_default_cooldown | Default cooldown period |
| autoscaling_group_health_check_type | Health check type |
| autoscaling_group_health_check_grace_period | Health check grace period |

### Launch Template

| Name | Description |
|------|-------------|
| launch_template_id | The ID of the launch template (null if not created) |
| launch_template_arn | The ARN of the launch template (null if not created) |
| launch_template_name | The name of the launch template (null if not created) |
| launch_template_latest_version | Latest version of the launch template |
| launch_template_default_version | Default version of the launch template |

### Warm Pool

| Name | Description |
|------|-------------|
| warm_pool_state | State of instances in the warm pool |

### Scaling Policies

| Name | Description |
|------|-------------|
| scaling_policy_arns | Map of scaling policy names to ARNs |

### Lifecycle Hooks

| Name | Description |
|------|-------------|
| lifecycle_hook_names | List of lifecycle hook names |

### Scheduled Actions

| Name | Description |
|------|-------------|
| schedule_arns | Map of schedule names to ARNs |

### ECS Integration

| Name | Description |
|------|-------------|
| ecs_capacity_provider_config | Configuration object for ECS capacity provider |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           Auto Scaling Group                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        Launch Template                                  │  │
│  │  • AMI, Instance Type, Security Groups                                 │  │
│  │  • User Data, IAM Profile, Metadata Options                            │  │
│  │  • Block Devices, Network Interfaces                                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     Mixed Instances Policy                              │  │
│  │  • On-Demand Base Capacity      • Spot Allocation Strategy             │  │
│  │  • Instance Type Overrides      • Attribute-based Selection            │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │     Warm Pool        │  │   Scaling Policies   │  │  Lifecycle Hooks   │  │
│  │  • Pre-initialized   │  │  • Target Tracking   │  │  • Launch hooks    │  │
│  │  • Stopped/Running   │  │  • Step Scaling      │  │  • Terminate hooks │  │
│  │  • Instance reuse    │  │  • Predictive        │  │  • SNS/SQS notify  │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │  Scheduled Actions   │  │   Traffic Sources    │  │   Notifications    │  │
│  │  • Cron schedules    │  │  • ELBv2 targets     │  │  • Launch events   │  │
│  │  • One-time scaling  │  │  • VPC Lattice       │  │  • Terminate events│  │
│  │  • Time zone support │  │                      │  │  • Error events    │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                       Instance Refresh                                  │  │
│  │  • Rolling updates   • Auto-rollback   • Alarm-based rollback          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    COMPUTE/AUTOSCALING TERRAFORM MODULE                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │    ASG CORE CONFIG              │   │      TIMING & COOLDOWN                  │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • min_size                      │   │ • default_cooldown                      │  ║
║  │ • tags                      │   │ • max_size                      │   │ • default_instance_warmup               │  ║
║  └──────────────┬──────────────┘   │ • desired_capacity              │   │ • wait_for_capacity_timeout             │  ║
║                 │                  │ • vpc_zone_identifier (required)│   └─────────────────────────────────────────┘  ║
║                 │                  └─────────────────────────────────┘                                                 ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "compute/autoscaling" }                              │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │ • asg_tags = merge(tags, { Name = var.name }, ecs_managed_tag_enabled ? { AmazonECSManaged = "true" } : {})           │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • launch_template_creation_enabled = var.launch_template_creation_enabled && var.launch_template != null                      │   │  ║
║  │  │ • enable_warm_pool = var.warm_pool != null                                                                │   │  ║
║  │  │ • enable_notifications = var.notifications != null                                                        │   │  ║
║  │  │ • enable_instance_refresh = var.instance_refresh != null                                                  │   │  ║
║  │  │ • enable_mixed_instances_policy = var.mixed_instances_policy != null                                      │   │  ║
║  │  │ • enable_instance_maintenance_policy = var.instance_maintenance_policy != null                            │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │   INSTANCE PROTECTION       │   │       HEALTH CHECKS             │   │       CAPACITY & SCALING                │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • scale_in_protection_enabled     │   │ • health_check_type (EC2/ELB)   │   │ • capacity_rebalance_enabled                    │  ║
║  │ • max_instance_lifetime     │   │ • health_check_grace_period     │   │ • termination_policies                  │  ║
║  │ • force_delete_enabled              │   └─────────────────────────────────┘   │ • suspended_processes                   │  ║
║  │ • ignore_desired_capacity   │                                         └─────────────────────────────────────────┘  ║
║  └─────────────────────────────┘                                                                                       ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │     CLOUDWATCH METRICS      │   │      SERVICE & LB               │   │        ECS & TAGS                       │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • enabled_metrics           │   │ • service_linked_role_arn       │   │ • ecs_managed_tag_enabled                           │  ║
║  │ • metrics_granularity       │   │ • target_group_arns             │   │ • tag_propagation_at_launch_enabled              │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                        LAUNCH TEMPLATE CONFIG                                                     │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • launch_template_creation_enabled          │ • launch_template (complex object):                                          │  ║
║  │ • launch_template_id              │   - image_id, instance_type, key_name, user_data, ebs_optimized             │  ║
║  │ • launch_template_name            │   - iam_instance_profile_arn/name, security_group_ids                       │  ║
║  │ • launch_template_version         │   - network_interfaces[], block_device_mappings[], metadata_options          │  ║
║  │                                   │   - monitoring_enabled, placement, instance_market_options (Spot)           │  ║
║  │                                   │   - cpu_options, credit_specification, capacity_reservation_specification   │  ║
║  │                                   │   - enclave_options, hibernation_options, license_specifications            │  ║
║  │                                   │   - maintenance_options, private_dns_name_options, instance_requirements    │  ║
║  │                                   │   - disable_api_termination/stop, elastic_gpu_specifications                │  ║
║  │                                   │   - tag_specifications[], update_default_version                            │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                      MIXED INSTANCES POLICY                                                       │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • mixed_instances_policy:                                                                                        │  ║
║  │   - instances_distribution: on_demand_allocation_strategy, on_demand_base_capacity,                              │  ║
║  │                             on_demand_percentage_above_base_capacity, spot_allocation_strategy,                  │  ║
║  │                             spot_instance_pools, spot_max_price                                                  │  ║
║  │   - launch_template_overrides[]: instance_type, weighted_capacity, launch_template_specification,                │  ║
║  │                                  instance_requirements (attribute-based selection)                               │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │    INSTANCE REFRESH         │   │        WARM POOL                │   │      MAINTENANCE POLICY                 │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • instance_refresh:         │   │ • warm_pool:                    │   │ • instance_maintenance_policy:          │  ║
║  │   - strategy (Rolling)      │   │   - pool_state (Stopped/        │   │   - min_healthy_percentage              │  ║
║  │   - triggers[]              │   │     Running/Hibernated)         │   │   - max_healthy_percentage              │  ║
║  │   - preferences:            │   │   - min_size                    │   └─────────────────────────────────────────┘  ║
║  │     · checkpoint_delay      │   │   - max_group_prepared_capacity │                                                ║
║  │     · checkpoint_percentages│   │   - instance_reuse_policy       │                                                ║
║  │     · instance_warmup       │   └─────────────────────────────────┘                                                ║
║  │     · min/max_healthy_%     │                                                                                       ║
║  │     · skip_matching         │                                                                                       ║
║  │     · auto_rollback         │                                                                                       ║
║  │     · alarm_specification   │                                                                                       ║
║  └─────────────────────────────┘                                                                                       ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │    LIFECYCLE HOOKS          │   │      NOTIFICATIONS              │   │      TRAFFIC SOURCES                    │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • lifecycle_hooks[]:        │   │ • notifications:                │   │ • traffic_sources[]:                    │  ║
║  │   - name                    │   │   - topic_arn (SNS)             │   │   - identifier (target group ARN)       │  ║
║  │   - lifecycle_transition    │   │   - notifications[]             │   │   - type (elbv2/vpc-lattice)            │  ║
║  │   - default_result          │   │     (LAUNCH, LAUNCH_ERROR,      │   └─────────────────────────────────────────┘  ║
║  │   - heartbeat_timeout       │   │      TERMINATE, TERMINATE_ERROR,│                                                ║
║  │   - notification_metadata   │   │      TEST_NOTIFICATION)         │                                                ║
║  │   - notification_target_arn │   └─────────────────────────────────┘                                                ║
║  │   - role_arn                │                                                                                       ║
║  └─────────────────────────────┘                                                                                       ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                         SCALING POLICIES                                                          │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • scaling_policies[]:                                                                                             │  ║
║  │   - name, policy_type (SimpleScaling/StepScaling/TargetTrackingScaling/PredictiveScaling)                        │  ║
║  │   - estimated_instance_warmup, enabled                                                                            │  ║
║  │   - adjustment_type (ChangeInCapacity/ExactCapacity/PercentChangeInCapacity)                                     │  ║
║  │   - min_adjustment_magnitude, cooldown, scaling_adjustment                                                        │  ║
║  │   - metric_aggregation_type, step_adjustments[]                                                                   │  ║
║  │   - target_tracking_configuration: target_value, scale_in_enabled, predefined/customized_metric_specification   │  ║
║  │   - predictive_scaling_configuration: mode, scheduling_buffer_time, max_capacity_breach_behavior,                │  ║
║  │                                       metric_specifications[]                                                     │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                         SCHEDULED ACTIONS                                                         │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • schedules[]:                                                                                                    │  ║
║  │   - name, min_size, max_size, desired_capacity                                                                   │  ║
║  │   - start_time, end_time, recurrence (cron), time_zone                                                           │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                aws_launch_template.this[0]                                                   │    ║
║    │                         (conditional: launch_template_creation_enabled = true)                                         │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ Configures: AMI, instance type, user data, IAM profile, security groups, block devices,                      │    ║
║    │             network interfaces, metadata options, monitoring, placement, spot options,                       │    ║
║    │             CPU options, credit spec, enclave/hibernation, maintenance, DNS options                          │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    aws_autoscaling_group.this                                                │    ║
║    │                                        (CORE RESOURCE)                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────┐   ┌─────────────────────┐   ┌───────────────────────┐   ┌────────────────────────┐     │    ║
║    │  │ launch_template │   │mixed_instances_policy│   │   instance_refresh    │   │instance_maintenance    │     │    ║
║    │  │   (dynamic)     │   │     (dynamic)       │   │      (dynamic)        │   │   _policy (dynamic)    │     │    ║
║    │  └─────────────────┘   └─────────────────────┘   └───────────────────────┘   └────────────────────────┘     │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────┐   ┌─────────────────────┐                                                              │    ║
║    │  │   warm_pool     │   │    tag (dynamic)    │                                                              │    ║
║    │  │   (dynamic)     │   │                     │                                                              │    ║
║    │  └─────────────────┘   └─────────────────────┘                                                              │    ║
║    │                                                                                                              │    ║
║    │  lifecycle { create_before_destroy = true }                                                                  │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                   ┌───────────────────────────────────────┼───────────────────────────────────────┐                    ║
║                   │                                       │                                       │                    ║
║                   ▼                                       ▼                                       ▼                    ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │ aws_autoscaling_policy.this  │    │aws_autoscaling_lifecycle     │    │  aws_autoscaling_schedule    │          ║
║    │       (for_each)             │    │        _hook.this            │    │        .this                 │          ║
║    ├──────────────────────────────┤    │       (for_each)             │    │      (for_each)              │          ║
║    │ • SimpleScaling              │    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • StepScaling                │    │ • EC2_INSTANCE_LAUNCHING     │    │ • Scheduled capacity         │          ║
║    │ • TargetTrackingScaling      │    │ • EC2_INSTANCE_TERMINATING   │    │ • Cron-based recurrence      │          ║
║    │ • PredictiveScaling          │    │ • SNS/SQS notifications      │    │ • Time-based start/end       │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                                                                                        ║
║                   ┌───────────────────────────────────────┬───────────────────────────────────────┐                    ║
║                   │                                       │                                       │                    ║
║                   ▼                                       ▼                                       ▼                    ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │ aws_autoscaling_notification │    │  aws_autoscaling_traffic     │    │                              │          ║
║    │         .this[0]             │    │  _source_attachment.this     │    │      (EC2 Instances)         │          ║
║    │    (count: 0 or 1)           │    │       (for_each)             │    │    Launched by ASG           │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • SNS topic integration      │    │ • elbv2 target groups        │    │ • Uses Launch Template       │          ║
║    │ • Event notifications        │    │ • vpc-lattice target groups  │    │ • Managed by ASG             │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         AUTO SCALING GROUP              │   │           LAUNCH TEMPLATE               │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • autoscaling_group_id                  │   │ • launch_template_id                    │                            ║
║  │ • autoscaling_group_arn                 │   │ • launch_template_arn                   │                            ║
║  │ • autoscaling_group_name                │   │ • launch_template_name                  │                            ║
║  │ • autoscaling_group_availability_zones  │   │ • launch_template_latest_version        │                            ║
║  │ • autoscaling_group_vpc_zone_identifier │   │ • launch_template_default_version       │                            ║
║  │ • autoscaling_group_min_size            │   └─────────────────────────────────────────┘                            ║
║  │ • autoscaling_group_max_size            │                                                                          ║
║  │ • autoscaling_group_desired_capacity    │   ┌─────────────────────────────────────────┐                            ║
║  │ • autoscaling_group_default_cooldown    │   │             WARM POOL                   │                            ║
║  │ • autoscaling_group_health_check_type   │   ├─────────────────────────────────────────┤                            ║
║  │ • autoscaling_group_health_check_grace_ │   │ • warm_pool_state                       │                            ║
║  │   period                                │   └─────────────────────────────────────────┘                            ║
║  └─────────────────────────────────────────┘                                                                          ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         SCALING POLICIES                │   │          LIFECYCLE HOOKS                │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • scaling_policy_arns (map)             │   │ • lifecycle_hook_names (list)           │                            ║
║  └─────────────────────────────────────────┘   └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │        SCHEDULED ACTIONS                │   │      ECS CAPACITY PROVIDER              │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • schedule_arns (map)                   │   │ • ecs_capacity_provider_config:         │                            ║
║  └─────────────────────────────────────────┘   │   - auto_scaling_group_arn              │                            ║
║                                                │   - managed_scaling_status              │                            ║
║                                                │   - managed_termination_protection      │                            ║
║                                                └─────────────────────────────────────────┘                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              DATA FLOW DIAGRAM                                                         ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║                                        ┌─────────────────────────┐                                                     ║
║                                        │    var.launch_template  │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║  var.launch_template_creation_enabled ──────► aws_launch_template.this[0]                                                       ║
║                                              │                                                                         ║
║  var.launch_template_id ─────────────────────┼──────────────────────────────────────┐                                  ║
║  var.launch_template_name ───────────────────┼──────────────────────────────────────┤                                  ║
║  var.launch_template_version ────────────────┼──────────────────────────────────────┤                                  ║
║                                              │                                      │                                  ║
║                                              ▼                                      ▼                                  ║
║                              ┌───────────────────────────────────────────────────────────┐                             ║
║  var.min_size ──────────────►│                                                           │                             ║
║  var.max_size ──────────────►│                                                           │                             ║
║  var.desired_capacity ──────►│                                                           │                             ║
║  var.vpc_zone_identifier ───►│                                                           │                             ║
║  var.health_check_* ────────►│              aws_autoscaling_group.this                   │                             ║
║  var.target_group_arns ─────►│                                                           │                             ║
║  var.mixed_instances_policy ►│                                                           │                             ║
║  var.instance_refresh ──────►│                                                           │                             ║
║  var.warm_pool ─────────────►│                                                           │                             ║
║  local.asg_tags ────────────►│                                                           │                             ║
║                              └────────────────────────────┬──────────────────────────────┘                             ║
║                                                           │                                                            ║
║           ┌───────────────────┬───────────────────┬───────┴───────┬───────────────────┬─────────────────────┐          ║
║           │                   │                   │               │                   │                     │          ║
║           ▼                   ▼                   ▼               ▼                   ▼                     ▼          ║
║  var.scaling_policies   var.lifecycle     var.schedules   var.notifications   var.traffic        EC2 Instances        ║
║           │             _hooks                  │               │            _sources                  │              ║
║           ▼                   ▼                 ▼               ▼                   ▼                   │              ║
║  aws_autoscaling_   aws_autoscaling_   aws_autoscaling_  aws_autoscaling_  aws_autoscaling_            │              ║
║  policy.this        lifecycle_hook     schedule.this     notification      traffic_source_             │              ║
║                     .this                                .this[0]          attachment.this             │              ║
║           │                   │                 │               │                   │                   │              ║
║           └───────────────────┴─────────────────┴───────────────┴───────────────────┴───────────────────┘              ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║                                                    MODULE OUTPUTS                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_launch_template` | 0 or 1 | Instance configuration (AMI, type, etc.) |
| `aws_autoscaling_group` | 1 | Core ASG resource |
| `aws_autoscaling_policy` | for_each | Scaling automation |
| `aws_autoscaling_lifecycle_hook` | for_each | Instance lifecycle events |
| `aws_autoscaling_schedule` | for_each | Time-based scaling |
| `aws_autoscaling_notification` | 0 or 1 | SNS event notifications |
| `aws_autoscaling_traffic_source_attachment` | for_each | ELBv2/VPC Lattice integration |

## FAQ

### Can I use different instance types with different scaling options?

AWS Auto Scaling supports **multiple instance types** within a single ASG, but with important limitations:

#### What IS Supported in a Single ASG

| Feature | Supported? | How |
|---------|------------|-----|
| Multiple instance types | Yes | `mixed_instances_policy.launch_template_overrides` |
| Mix of On-Demand + Spot | Yes | `mixed_instances_policy.instances_distribution` |
| Weighted capacity per type | Yes | `weighted_capacity` in overrides |
| Attribute-based selection | Yes | `instance_requirements` in overrides |

**Example with multiple instance types:**

```hcl
mixed_instances_policy = {
  instances_distribution = {
    on_demand_base_capacity                  = 1      # Always keep 1 On-Demand
    on_demand_percentage_above_base_capacity = 25     # 25% On-Demand, 75% Spot
    spot_allocation_strategy                 = "capacity-optimized"
  }
  launch_template_overrides = [
    { instance_type = "m5.large",  weighted_capacity = 1 },
    { instance_type = "m5.xlarge", weighted_capacity = 2 },
    { instance_type = "c5.large",  weighted_capacity = 1 },
  ]
}
```

**Example with attribute-based instance selection:**

```hcl
mixed_instances_policy = {
  launch_template_overrides = [
    {
      instance_requirements = {
        vcpu_count            = { min = 2, max = 8 }
        memory_mib            = { min = 4096, max = 16384 }
        cpu_manufacturers     = ["intel", "amd"]
        burstable_performance = "excluded"
        instance_generations  = ["current"]
      }
    }
  ]
}
```

#### What is NOT Supported in a Single ASG

| Feature | Supported? | Alternative |
|---------|------------|-------------|
| Different scaling policies per instance type | **No** | Use separate ASGs |
| Different min/max per instance type | **No** | Use separate ASGs |
| Different health checks per instance type | **No** | Use separate ASGs |

Scaling policies apply to the **entire ASG**, not per instance type:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Auto Scaling Group                           │
├─────────────────────────────────────────────────────────────────┤
│  Instance Types: m5.large, m5.xlarge, c5.large (mixed)         │
│                                                                 │
│  Scaling Policies (apply to ALL instances):                     │
│    • Target Tracking: CPU at 70%                                │
│    • Step Scaling: Scale out when requests > 1000               │
└─────────────────────────────────────────────────────────────────┘
```

#### Solution: Use Separate ASGs for Different Scaling Behavior

If you need different scaling policies per instance type, create multiple ASG module instances:

```hcl
# ASG 1: Baseline workers with CPU-based scaling
module "baseline_asg" {
  source = "..."
  name   = "baseline-workers"

  min_size = 2
  max_size = 10

  launch_template = {
    instance_type = "m5.large"
  }

  scaling_policies = [{
    name        = "cpu-scaling"
    policy_type = "TargetTrackingScaling"
    target_tracking_configuration = {
      target_value = 70.0
      predefined_metric_specification = {
        predefined_metric_type = "ASGAverageCPUUtilization"
      }
    }
  }]
}

# ASG 2: Burst workers with queue-based scaling
module "burst_asg" {
  source = "..."
  name   = "burst-workers"

  min_size = 0
  max_size = 50

  launch_template = {
    instance_type = "c5.xlarge"
  }

  mixed_instances_policy = {
    instances_distribution = {
      on_demand_percentage_above_base_capacity = 0  # 100% Spot
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  scaling_policies = [{
    name        = "queue-scaling"
    policy_type = "TargetTrackingScaling"
    target_tracking_configuration = {
      target_value = 100.0
      customized_metric_specification = {
        metric_name = "ApproximateNumberOfMessagesVisible"
        namespace   = "AWS/SQS"
        statistic   = "Average"
        dimensions  = [{ name = "QueueName", value = "my-queue" }]
      }
    }
  }]
}
```

## Notes

- When using `mixed_instances_policy`, the launch template block is handled within the policy
- IMDSv2 is enforced by default when creating a launch template (`http_tokens = "required"`)
- EBS volumes are encrypted by default in the launch template
- Set `ecs_managed_tag_enabled = true` to add the `AmazonECSManaged` tag required for ECS capacity providers
- The `ignore_desired_capacity_changes` variable exists for documentation; to ignore capacity changes, set `desired_capacity = null`
- Warm pool instances can be in Stopped, Running, or Hibernated states
- Lifecycle hooks support SNS topics or SQS queues as notification targets
- Traffic sources support both ELBv2 (ALB/NLB) and VPC Lattice target groups
