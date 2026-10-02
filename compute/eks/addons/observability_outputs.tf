################################################################################
# S3-backed metrics and traces
################################################################################

output "cluster_arn" {
  description = "ARN of the EKS cluster whose observability stores Operator queries."
  value       = data.aws_eks_cluster.this.arn
}

output "prometheus_remote_write_endpoint" {
  description = "Prometheus ingestion URL, distinct from the Thanos query endpoint (null unless prometheus is selected)."
  value       = local.prometheus_remote_write_endpoint
}

output "prometheus_s3_bucket" {
  description = "Dedicated metrics bucket, created or supplied (null when managed Thanos storage is off)."
  value       = local.thanos_bucket_name
}

output "prometheus_s3_bucket_arn" {
  description = "ARN of the Thanos metrics bucket (null when managed Thanos storage is off)."
  value       = local.thanos_bucket_arn
}

output "thanos_role_arns" {
  description = "Pod Identity roles keyed by sidecar, store, and compactor; empty when Thanos is disabled."
  value       = { for name, role in module.thanos_role : name => role.role_arn }
}

output "traces_providers" {
  description = "Trace destinations selected for this cluster; empty when traces are off."
  value       = tolist(local.traces_providers)
}

output "tempo_endpoint" {
  description = "Private Tempo HTTP query URL for Grafana/TraceQL (null when traces are off). No native Ravion trace tab is configured."
  value       = local.tempo_endpoint
}

output "tempo_s3_bucket" {
  description = "Dedicated trace bucket, created or supplied (null when traces are off)."
  value       = local.tempo_bucket_name
}

output "tempo_s3_bucket_arn" {
  description = "ARN of the Tempo trace bucket (null when traces are off)."
  value       = local.tempo_bucket_arn
}

output "tempo_role_arn" {
  description = "Tempo Pod Identity role scoped to the trace bucket (null when traces are off)."
  value       = local.tempo_enabled ? module.tempo_role[0].role_arn : null
}

output "traces_otlp_grpc_endpoint" {
  description = "Private OTLP/gRPC base URL for instrumented applications (null when traces are off). Use with OTEL_EXPORTER_OTLP_PROTOCOL=grpc."
  value       = local.traces_otlp_grpc_endpoint
}

output "traces_otlp_http_endpoint" {
  description = "Private OTLP/HTTP base URL (null when traces are off). Use OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf; signal-specific URLs append /v1/traces."
  value       = local.traces_otlp_http_endpoint
}

output "tempo_chart_version" {
  description = "Installed Tempo Helm chart version (null when traces are off)."
  value       = local.tempo_enabled ? helm_release.tempo[0].version : null
}
