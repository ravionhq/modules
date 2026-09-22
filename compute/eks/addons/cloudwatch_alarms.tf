# Interruption events are short-lived; detect stalled consumption before expiry.
resource "aws_cloudwatch_metric_alarm" "karpenter_interruption_queue_age" {
  count = var.karpenter_enabled && var.karpenter_interruption_queue_alarm_creation_enabled ? 1 : 0

  alarm_name          = "${module.karpenter[0].interruption_queue_name}-oldest-message-age"
  alarm_description   = "Karpenter interruption messages are waiting to be processed. Check controller health and queue access."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.karpenter_interruption_queue_alarm_age_threshold_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.karpenter_interruption_queue_alarm_actions
  ok_actions          = var.karpenter_interruption_queue_alarm_ok_actions

  dimensions = {
    QueueName = module.karpenter[0].interruption_queue_name
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.karpenter_interruption_queue_alarm_age_threshold_seconds < var.karpenter_interruption_queue_message_retention_seconds
      error_message = "The interruption queue age threshold must be below its message retention period."
    }
  }
}
