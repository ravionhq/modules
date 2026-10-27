resource "aws_cloudfront_monitoring_subscription" "this" {
  for_each = var.additional_metrics_enabled ? aws_cloudfront_distribution.this : {}

  distribution_id = each.value.id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}
