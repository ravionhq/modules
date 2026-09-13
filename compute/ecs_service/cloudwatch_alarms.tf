################################################################################
# CloudWatch Alarms
#
# Service-level alarms on ECS utilization, Container Insights task counts,
# and (when a load balancer is attached) target group health. Load balancer
# level alarms (ELB 5xx, etc.) belong to the ALB / cluster modules.
################################################################################

locals {
  create_cloudwatch_alarms = var.cloudwatch_alarms_creation_enabled

  # ALB target group alarms need the LoadBalancer + TargetGroup dimensions.
  alb_target_alarms_enabled = (
    local.create_cloudwatch_alarms
    && local.enable_load_balancer
    && !local.enable_nlb_listener
    && try(length(var.load_balancer_attachment.listener_rules), 0) > 0
  )

  # NLB services can have one target group per listener; alarm on each.
  nlb_alarm_target_groups = local.create_cloudwatch_alarms && local.enable_nlb_listener ? merge(
    { primary = aws_lb_target_group.tg_1[0].arn_suffix },
    { for port, tg in aws_lb_target_group.nlb_additional : port => tg.arn_suffix }
  ) : {}

  cloudwatch_alarm_name_prefix = "${var.name}-ecs"
}

################################################################################
# Service utilization (AWS/ECS)
################################################################################

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-cpu-utilization"
  alarm_description   = "ECS service CPU utilization for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-memory-utilization"
  alarm_description   = "ECS service memory utilization for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

################################################################################
# Running task count (ECS/ContainerInsights)
#
# Requires Container Insights on the cluster. When it is disabled the metric
# never reports and the alarm stays in INSUFFICIENT_DATA / OK because missing
# data is treated as not breaching.
################################################################################

resource "aws_cloudwatch_metric_alarm" "running_tasks" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-running-tasks"
  alarm_description   = "ECS running task count below minimum for ${var.name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = var.cloudwatch_alarm_period
  statistic           = "Minimum"
  threshold           = var.cloudwatch_alarm_running_tasks_minimum
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

################################################################################
# ALB target group health (AWS/ApplicationELB)
################################################################################

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = local.alb_target_alarms_enabled ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-unhealthy-hosts"
  alarm_description   = "Unhealthy ALB targets for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Maximum"
  threshold           = var.cloudwatch_alarm_unhealthy_hosts_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.attached[0].arn_suffix
    TargetGroup  = aws_lb_target_group.tg_1[0].arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = local.alb_target_alarms_enabled ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-target-5xx"
  alarm_description   = "Target 5xx responses for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_target_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.attached[0].arn_suffix
    TargetGroup  = aws_lb_target_group.tg_1[0].arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  count = local.alb_target_alarms_enabled ? 1 : 0

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-target-response-time"
  alarm_description   = "Average target response time for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_target_response_time_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.attached[0].arn_suffix
    TargetGroup  = aws_lb_target_group.tg_1[0].arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

################################################################################
# NLB target group health (AWS/NetworkELB)
################################################################################

resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy_hosts" {
  for_each = local.nlb_alarm_target_groups

  alarm_name          = "${local.cloudwatch_alarm_name_prefix}-${each.key}-unhealthy-hosts"
  alarm_description   = "Unhealthy NLB targets (${each.key}) for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Maximum"
  threshold           = var.cloudwatch_alarm_unhealthy_hosts_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.attached[0].arn_suffix
    TargetGroup  = each.value
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
