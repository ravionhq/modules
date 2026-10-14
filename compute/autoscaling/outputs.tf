################################################################################
# Auto Scaling Group
################################################################################

output "autoscaling_group_id" {
  description = "The ID of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.id
}

output "autoscaling_group_arn" {
  description = "The ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.arn
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_availability_zones" {
  description = "The availability zones of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.availability_zones
}

output "autoscaling_group_vpc_zone_identifier" {
  description = "The VPC zone identifier (subnet IDs) of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.vpc_zone_identifier
}

output "autoscaling_group_min_size" {
  description = "The minimum size of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.min_size
}

output "autoscaling_group_max_size" {
  description = "The maximum size of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.max_size
}

output "autoscaling_group_desired_capacity" {
  description = "The desired capacity of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.desired_capacity
}

output "autoscaling_group_default_cooldown" {
  description = "The default cooldown period of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.default_cooldown
}

output "autoscaling_group_health_check_type" {
  description = "The health check type of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.health_check_type
}

output "autoscaling_group_health_check_grace_period" {
  description = "The health check grace period of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.health_check_grace_period
}

################################################################################
# Launch Template
################################################################################

output "launch_template_id" {
  description = "The ID of the launch template (null if not created)."
  value       = local.create_launch_template ? aws_launch_template.this[0].id : null
}

output "launch_template_arn" {
  description = "The ARN of the launch template (null if not created)."
  value       = local.create_launch_template ? aws_launch_template.this[0].arn : null
}

output "launch_template_name" {
  description = "The name of the launch template (null if not created)."
  value       = local.create_launch_template ? aws_launch_template.this[0].name : null
}

output "launch_template_latest_version" {
  description = "The latest version of the launch template (null if not created)."
  value       = local.create_launch_template ? aws_launch_template.this[0].latest_version : null
}

output "launch_template_default_version" {
  description = "The default version of the launch template (null if not created)."
  value       = local.create_launch_template ? aws_launch_template.this[0].default_version : null
}

################################################################################
# Warm Pool
################################################################################

output "warm_pool_state" {
  description = "The state of instances in the warm pool (null if warm pool not enabled)."
  value       = local.enable_warm_pool ? var.warm_pool.pool_state : null
}

################################################################################
# Scaling Policies
################################################################################

output "scaling_policy_arns" {
  description = "Map of scaling policy names to their ARNs."
  value = {
    for name, policy in aws_autoscaling_policy.this : name => policy.arn
  }
}

################################################################################
# Lifecycle Hooks
################################################################################

output "lifecycle_hook_names" {
  description = "List of lifecycle hook names created."
  value       = [for hook in aws_autoscaling_lifecycle_hook.this : hook.name]
}

################################################################################
# Scheduled Actions
################################################################################

output "schedule_arns" {
  description = "Map of scheduled action names to their ARNs."
  value = {
    for name, schedule in aws_autoscaling_schedule.this : name => schedule.arn
  }
}

################################################################################
# ECS Capacity Provider Configuration
################################################################################

output "ecs_capacity_provider_config" {
  description = "Configuration object for creating an ECS capacity provider with this ASG."
  value = {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_scaling_status         = "ENABLED"
    managed_termination_protection = var.scale_in_protection_enabled ? "ENABLED" : "DISABLED"
  }
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}

output "mixed_instances_policy_enabled" {
  description = "Whether the ASG uses a mixed-instances (spot) policy."
  value       = length(aws_autoscaling_group.this.mixed_instances_policy) > 0
}

output "spot_instances_distribution" {
  description = "The instances_distribution of the mixed-instances policy, null when spot is disabled."
  value       = try(aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0], null)
}
