################################################################################
# Application Auto Scaling Target
################################################################################

resource "aws_appautoscaling_target" "this" {
  count = local.auto_scaling_enabled ? 1 : 0

  max_capacity       = var.auto_scaling.max_capacity
  min_capacity       = var.auto_scaling.min_capacity
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = local.tags
}

################################################################################
# Target Tracking Scaling Policies
################################################################################

resource "aws_appautoscaling_policy" "target_tracking" {
  for_each = local.auto_scaling_enabled ? {
    for idx, policy in var.auto_scaling.target_tracking : policy.policy_name => policy
  } : {}

  name               = each.value.policy_name
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
    disable_scale_in   = !each.value.scale_in_enabled

    # Predefined metric
    dynamic "predefined_metric_specification" {
      for_each = each.value.predefined_metric != null ? [each.value.predefined_metric] : []
      content {
        predefined_metric_type = predefined_metric_specification.value
        resource_label = predefined_metric_specification.value == "ALBRequestCountPerTarget" ? (
          local.enable_load_balancer && !local.enable_nlb_listener ? try("${data.aws_lb.attached[0].arn_suffix}/${local.primary_target_group_arn_suffix}", null) : null
        ) : null
      }
    }

    # Custom metric
    dynamic "customized_metric_specification" {
      for_each = each.value.custom_metric != null ? [each.value.custom_metric] : []
      content {
        metric_name = customized_metric_specification.value.metric_name
        namespace   = customized_metric_specification.value.namespace
        statistic   = customized_metric_specification.value.statistic

        dynamic "dimensions" {
          for_each = customized_metric_specification.value.dimensions
          content {
            name  = dimensions.key
            value = dimensions.value
          }
        }
      }
    }
  }
}

################################################################################
# Scheduled Scaling Actions
################################################################################

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = local.auto_scaling_enabled && var.auto_scaling.scheduled != null ? {
    for action in var.auto_scaling.scheduled : action.name => action
  } : {}

  name               = each.value.name
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  schedule   = each.value.schedule
  timezone   = each.value.timezone
  start_time = each.value.start_time
  end_time   = each.value.end_time

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}

################################################################################
# Local for Target Group ARN Suffix (for ALBRequestCountPerTarget)
################################################################################

locals {
  primary_target_group_arn_suffix = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn_suffix : ""
}

