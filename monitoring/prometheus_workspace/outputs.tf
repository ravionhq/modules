################################################################################
# Workspace
################################################################################

output "workspace_id" {
  description = "The workspace ID."
  value       = aws_prometheus_workspace.this.id
}

output "workspace_arn" {
  description = "The workspace ARN, for scoping aps:RemoteWrite and aps:QueryMetrics permissions to it."
  value       = aws_prometheus_workspace.this.arn
}

output "query_url" {
  description = "The workspace's Prometheus-compatible query endpoint, for a Grafana Prometheus data source with SigV4 authentication."
  value       = local.query_url
}

output "remote_write_url" {
  description = "The workspace's remote write endpoint, for senders signing with SigV4."
  value       = local.remote_write_url
}

output "retention_period_in_days" {
  description = "Number of days the workspace keeps samples."
  value       = aws_prometheus_workspace_configuration.this.retention_period_in_days
}

output "region" {
  description = "The AWS region the workspace is in."
  value       = local.region
}
