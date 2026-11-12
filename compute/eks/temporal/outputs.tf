output "release_name" {
  description = "Name of the Temporal Helm release. Every Service it creates is prefixed with it."
  value       = helm_release.temporal.name
}

output "namespace" {
  description = "Kubernetes namespace Temporal runs in."
  value       = helm_release.temporal.namespace
}

output "chart_version" {
  description = "Version of the upstream Temporal chart installed."
  value       = helm_release.temporal.version
}

output "frontend_address" {
  description = "In-cluster gRPC address of the Temporal frontend, host:port, for SDK clients and the CLI (TEMPORAL_ADDRESS)."
  value       = "${local.frontend_host}:${local.frontend_port}"
}

output "frontend_host" {
  description = "In-cluster host name of the Temporal frontend Service."
  value       = local.frontend_host
}

output "frontend_port" {
  description = "gRPC port of the Temporal frontend."
  value       = local.frontend_port
}

output "frontend_http_address" {
  description = "In-cluster address of the frontend's HTTP API, host:port."
  value       = "${local.frontend_host}:${local.frontend_http_port}"
}

output "temporal_namespaces" {
  description = "Temporal namespaces the module creates on install."
  value       = keys(var.temporal_namespaces)
}

output "num_history_shards" {
  description = "Number of history shards the cluster was configured with."
  value       = var.num_history_shards
}

output "web_address" {
  description = "In-cluster URL of the Web UI (null when the Web UI is off)."
  value       = var.web_enabled ? "http://${local.web_host}:8080" : null
}

output "web_url" {
  description = "URL of the Web UI through its Ingress (null unless the Ingress is enabled with a host)."
  value       = var.web_enabled && var.web_ingress_enabled && var.web_ingress_host != null ? "${var.web_ingress_certificate_arn != null || !local.web_ingress_alb ? "https" : "http"}://${var.web_ingress_host}" : null
}

output "tls_enabled" {
  description = "Whether the frontend serves TLS. SDK clients must then connect with TLS."
  value       = var.tls_enabled
}

output "tls_server_name" {
  description = "Name SDK clients verify the frontend certificate against (null when TLS is off)."
  value       = var.tls_enabled ? local.frontend_host : null
}

output "tls_ca_secret_name" {
  description = "Kubernetes Secret in the namespace whose ca.crt is the CA SDK clients trust for the frontend (null when TLS is off). Copy only ca.crt to clients: the Secret also holds the frontend's private key."
  value       = var.tls_enabled ? local.tls_frontend_secret : null
}

output "database_endpoint" {
  description = "Endpoint of the Aurora cluster Temporal uses."
  value       = local.database_host
}

output "database_secret_name" {
  description = "Kubernetes Secret holding the database password."
  value       = local.database_secret_name
}

output "priority_class_name" {
  description = "PriorityClass the Temporal pods run with (null when none)."
  value       = local.priority_class_name
}

output "node_pool_name" {
  description = "Dedicated Karpenter NodePool Temporal runs on (null when not created)."
  value       = var.node_pool_creation_enabled ? local.node_pool_name : null
}
