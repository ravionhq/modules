################################################################################
# Workspace
################################################################################

output "workspace_id" {
  description = "The Grafana workspace ID."
  value       = aws_grafana_workspace.this.id
}

output "workspace_arn" {
  description = "The Grafana workspace ARN."
  value       = aws_grafana_workspace.this.arn
}

output "url" {
  description = "The Grafana workspace's sign-in URL."
  value       = "https://${aws_grafana_workspace.this.endpoint}"
}

output "grafana_version" {
  description = "The Grafana version the workspace runs."
  value       = aws_grafana_workspace.this.grafana_version
}

output "role_arn" {
  description = "The role the workspace reads AWS data with."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the role the workspace reads AWS data with, for attaching further read policies."
  value       = aws_iam_role.this.name
}

output "data_source_uids" {
  description = "UIDs of the Grafana data sources the module manages, for dashboards that reference them."
  value       = [for data_source in local.data_sources : data_source.uid]
}

output "region" {
  description = "The AWS region the workspace is in."
  value       = local.region
}
