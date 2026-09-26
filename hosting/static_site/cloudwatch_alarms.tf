# CloudFront publishes global distribution metrics in us-east-1.
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  provider = aws.us_east_1
  for_each = var.cloudwatch_alarms_creation_enabled ? var.distributions : {}

  alarm_name          = "${var.name}-${each.key}-cloudfront-5xx-error-rate"
  alarm_description   = "CloudFront 5xx error percentage for ${var.name} (${each.key}). Check access logs, origin availability and CloudFront Functions."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_error_rate_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = module.cdn.distribution_ids[each.key]
    Region         = "Global"
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}
