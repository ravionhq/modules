################################################################################
# CloudWatch Alarms
#
# The request alarms use the LoadBalancer dimension only. This module creates
# no target groups (services attach their own, some at runtime through the AWS
# Load Balancer Controller), so the unhealthy host alarm queries every target
# group behind the load balancer with CloudWatch Metrics Insights instead of
# naming them.
################################################################################

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-alb-elb-5xx"
  alarm_description   = "ALB-generated 5xx responses for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_elb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-alb-target-5xx"
  alarm_description   = "Target 5xx responses behind ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_target_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-alb-target-response-time"
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
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-alb-unhealthy-hosts"
  alarm_description   = "Unhealthy targets in any target group behind ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  threshold           = var.cloudwatch_alarm_unhealthy_hosts_threshold
  treat_missing_data  = "notBreaching"

  # MAX without GROUP BY folds every target group into one series, so a single
  # alarm covers target groups created after this one, with no Terraform change.
  metric_query {
    id          = "unhealthy_hosts"
    expression  = "SELECT MAX(UnHealthyHostCount) FROM SCHEMA(\"AWS/ApplicationELB\", LoadBalancer, TargetGroup) WHERE LoadBalancer = '${aws_lb.this.arn_suffix}'"
    period      = var.cloudwatch_alarm_period
    return_data = true
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
