################################################################################
# Artifact Registry Repository
################################################################################

output "artifact_registry_repository_id" {
  description = "Fully qualified ID of the Artifact Registry repository (null if disabled)."
  value       = one(google_artifact_registry_repository.this[*].id)
}

output "artifact_registry_repository_url" {
  description = "Image path prefix of the repository, <region>-docker.pkg.dev/<project>/<repository>/<name>, which the chart deploys (null if disabled)."
  value       = var.artifact_registry_repository_creation_enabled ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this[0].repository_id}/${var.name}" : null
}

################################################################################
# Load balancer
################################################################################

output "gateway_address_name" {
  description = "Name of the reserved address the chart's Gateway uses (null for a cluster-only workload)."
  value       = local.load_balancer_enabled ? local.gateway_address_name : null
}

output "gateway_address" {
  description = "IP address of the workload's Gateway (null for a cluster-only workload)."
  value       = local.gateway_address
}

output "load_balancer_url" {
  description = "URL of the workload through its Gateway: https when a certificate is configured, the first hostname without a wildcard, otherwise the Gateway address (null for a cluster-only workload)."
  value       = local.load_balancer_url
}

output "load_balancer_source_cidr_blocks" {
  description = "Ranges the load balancer reaches pods from, sorted: Google's health check ranges, plus the proxy-only subnet for an internal Gateway. The chart's NetworkPolicy admits them (empty for a cluster-only workload)."
  value       = local.load_balancer_source_cidr_blocks
}

################################################################################
# Service addresses
################################################################################

output "service_host" {
  description = "In-cluster DNS name of the workload's Kubernetes Service, <release_name>.<release_namespace>.svc.cluster.local (null unless kubernetes_service_enabled)."
  value       = local.service_host
}

output "service_port" {
  description = "Port the workload's Kubernetes Service listens on (null unless kubernetes_service_enabled)."
  value       = var.kubernetes_service_enabled ? var.container_port : null
}

output "service_url" {
  description = "In-cluster URL of the workload (null unless kubernetes_service_enabled)."
  value       = local.service_url
}

################################################################################
# Workload Identity
################################################################################

output "workload_identity_service_account_email" {
  description = "Email of the workload's Google service account. Annotate the release's Kubernetes service account with iam.gke.io/gcp-service-account set to it; grant it access to resources in other projects (null unless roles are granted)."
  value       = one(google_service_account.workload_identity[*].email)
}

output "workload_identity_service_account_member" {
  description = "IAM member (serviceAccount:<email>) of the workload's Google service account (null unless roles are granted)."
  value       = one(google_service_account.workload_identity[*].member)
}

################################################################################
# General
################################################################################

output "project_id" {
  description = "Project the resources are created in."
  value       = var.project_id
}

output "region" {
  description = "Region the regional resources are created in."
  value       = var.region
}
