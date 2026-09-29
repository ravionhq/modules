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
  count = var.metrics_enabled ? 1 : 0

  name              = local.metrics_log_group_name
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days

  tags = local.tags
}
