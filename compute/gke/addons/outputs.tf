output "cluster_name" {
  description = "Name of the GKE cluster the add-ons are installed onto."
  value       = var.cluster_name
}

output "cert_manager_namespace" {
  description = "Namespace of cert-manager, or null when it is not installed."
  value       = var.cert_manager_enabled ? var.cert_manager_namespace : null
}

output "keda_namespace" {
  description = "Namespace of KEDA, or null when it is not installed."
  value       = var.keda_enabled ? var.keda_namespace : null
}

output "eso_namespace" {
  description = "Namespace of the External Secrets Operator, or null when it is not installed."
  value       = var.eso_enabled ? var.eso_namespace : null
}

output "eso_cluster_secret_store_name" {
  description = "Name of the Secret Manager ClusterSecretStore, or null when it is not created."
  value       = var.eso_enabled && var.eso_cluster_secret_store_creation_enabled ? var.eso_cluster_secret_store_name : null
}

output "eso_principal" {
  description = "Workload Identity principal of the External Secrets controller, for granting it access to secrets in other projects. Null when the operator is not installed."
  value       = var.eso_enabled ? local.eso_principal : null
}
