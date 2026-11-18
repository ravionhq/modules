################################################################################
# Cluster
################################################################################

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified ID of the cluster (projects/<project>/locations/<region>/clusters/<name>)."
  value       = google_container_cluster.this.id
}

output "project_id" {
  description = "Project the cluster runs in."
  value       = var.project_id
}

output "region" {
  description = "Region of the regional cluster."
  value       = google_container_cluster.this.location
}

output "kubernetes_version" {
  description = "Current control plane version."
  value       = google_container_cluster.this.master_version
}

output "endpoint" {
  description = "IP address of the control plane endpoint: private unless the public IP endpoint is enabled."
  value       = google_container_cluster.this.endpoint
}

output "dns_endpoint" {
  description = "DNS-based control plane endpoint. Authorized by IAM, and reachable from outside the VPC when dns_endpoint_enabled is true."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "dns_endpoint_external_access_enabled" {
  description = "Whether the DNS-based endpoint accepts requests from outside the VPC."
  value       = var.dns_endpoint_enabled
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the IP-based control plane endpoint."
  value       = one(google_container_cluster.this.master_auth[*].cluster_ca_certificate)
}

output "workload_identity_pool" {
  description = "Workload Identity pool of the cluster (<project>.svc.id.goog)."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

################################################################################
# Network
################################################################################

output "network" {
  description = "VPC network the cluster runs in."
  value       = google_container_cluster.this.network
}

output "subnetwork" {
  description = "Subnetwork the nodes run in."
  value       = google_container_cluster.this.subnetwork
}

################################################################################
# Nodes and access
################################################################################

output "node_service_account_email" {
  description = "Service account the nodes run as."
  value       = local.node_service_account_email
}

output "node_pool_names" {
  description = "Generated names of the node pools, keyed by pool key (system and each additional pool)."
  value       = { for key, pool in google_container_node_pool.this : key => pool.name }
}

output "system_node_labels" {
  description = "Kubernetes labels on the system node pool."
  value       = local.system_node_labels
}

output "system_node_min_nodes" {
  description = "Minimum node count of the system node pool across all zones."
  value       = var.system_node_pool.min_nodes
}

output "ravion_runner_service_account_email" {
  description = "Service account granted roles/container.admin for Ravion pipelines, or null when that grant is off."
  value       = var.ravion_runner_cluster_admin_enabled ? local.ravion_runner_service_account_email : null
}
