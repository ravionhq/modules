################################################################################
# CloudWatch Log Groups
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days

  tags = local.tags
}

# The embedded metric format logs CloudWatch extracts the metrics from. Created
# here so they get the same retention, and so the task role can be scoped to it.
resource "aws_cloudwatch_log_group" "metrics" {
  count = local.metrics_destination == "cloudwatch" ? 1 : 0

  name              = local.metrics_log_group_name
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days

  tags = local.tags
}

# The OTLP log records senders export, one JSON event per record with its trace
# and span IDs.
resource "aws_cloudwatch_log_group" "otlp_logs" {
  count = var.logs_enabled ? 1 : 0

  name              = local.otlp_log_group_name
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days

  tags = local.tags
}
