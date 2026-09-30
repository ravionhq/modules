################################################################################
# Workspace
################################################################################

resource "aws_prometheus_workspace" "this" {
  alias       = var.name
  kms_key_arn = local.kms_key_arn

  tags = local.tags
}

resource "aws_prometheus_workspace_configuration" "this" {
  workspace_id             = aws_prometheus_workspace.this.id
  retention_period_in_days = var.retention_period_in_days
}
