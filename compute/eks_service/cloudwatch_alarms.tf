################################################################################
# CloudWatch Alarms
#
# ALB publishes UnHealthyHostCount per target group, and this module owns the
# workload's target group, so the alarm lives here rather than on the shared
# load balancer. Plain LoadBalancer + TargetGroup dimensions (not a Metrics
# Insights query) keep the alarm readable by tools that inspect alarm metrics.
# Load balancer wide alarms (ELB 5xx, response time) belong to networking/alb.
################################################################################

locals {
  unhealthy_hosts_alarm_enabled = var.cloudwatch_alarms_creation_enabled && local.enable_load_balancer
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = local.unhealthy_hosts_alarm_enabled ? 1 : 0

  alarm_name          = "${var.name}-unhealthy-hosts"
  alarm_description   = "Unhealthy load balancer targets for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Maximum"
  threshold           = var.cloudwatch_alarm_unhealthy_hosts_threshold
  # No pods registered (or no traffic yet) publishes nothing: not a failure.
  treat_missing_data = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.attached[0].arn_suffix
    TargetGroup  = aws_lb_target_group.this[0].arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
