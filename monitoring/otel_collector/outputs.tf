################################################################################
# Endpoints
################################################################################

output "hostname" {
  description = "The collector's private DNS name, resolvable inside the VPC."
  value       = local.hostname
}

output "otlp_grpc_endpoint" {
  description = "OTLP/gRPC endpoint, for OTEL_EXPORTER_OTLP_ENDPOINT with the grpc protocol."
  value       = "http://${local.hostname}:${local.otlp_grpc_port}"
}

output "otlp_http_endpoint" {
  description = "OTLP/HTTP base endpoint. Senders append /v1/traces or /v1/metrics."
  value       = "http://${local.hostname}:${local.otlp_http_port}"
}

output "otlp_grpc_port" {
  description = "The port the collector accepts OTLP/gRPC on."
  value       = local.otlp_grpc_port
}

output "otlp_http_port" {
  description = "The port the collector accepts OTLP/HTTP on."
  value       = local.otlp_http_port
}

################################################################################
# Network
################################################################################

output "security_group_id" {
  description = "The ID of the collector's security group."
  value       = module.security_group.security_group_id
}

output "service_discovery_namespace_id" {
  description = "The ID of the collector's Cloud Map private DNS namespace."
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "service_discovery_hosted_zone_id" {
  description = "The Route 53 private hosted zone behind the namespace, for associating another VPC with it."
  value       = aws_service_discovery_private_dns_namespace.this.hosted_zone
}

################################################################################
# ECS
################################################################################

output "cluster_arn" {
  description = "The ARN of the collector's ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "The name of the collector's ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "The name of the collector's ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "The ARN of the collector's current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  description = "The ARN of the role the collector calls AWS with."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "The name of the role the collector calls AWS with, for attaching further policies."
  value       = aws_iam_role.task.name
}

################################################################################
# Logs
################################################################################

output "log_group_name" {
  description = "The CloudWatch log group holding the collector's own logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_stream_prefix" {
  description = "The prefix of the collector's log streams in log_group_name."
  value       = local.log_stream_prefix
}

output "metrics_log_group_name" {
  description = "The CloudWatch log group metrics are published through, or null while metrics are disabled."
  value       = var.metrics_enabled ? aws_cloudwatch_log_group.metrics[0].name : null
}

output "region" {
  description = "The AWS region the collector runs in and exports to."
  value       = local.region
}
