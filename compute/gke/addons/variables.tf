################################################################################
# Cluster
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the existing GKE cluster to install the add-ons onto."

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster_name must be a GKE cluster name: 1-40 lowercase letters, numbers, and hyphens."
  }
}

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project the cluster runs in."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a Google Cloud project ID: 6-30 lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "region" {
  type        = string
  description = "Region of the regional cluster, such as us-central1."
}

variable "use_dns_endpoint" {
  type        = bool
  description = "Reach the Kubernetes API through the cluster's DNS-based endpoint. Set false when the cluster does not allow external traffic on that endpoint; the runner must then reach the IP endpoint."
  default     = true
}

################################################################################
# Add-on placement
################################################################################

variable "addon_placement_enabled" {
  type        = bool
  description = "Keep add-on pods off Spot and preemptible nodes, prefer the system node pool, and tolerate CriticalAddonsOnly."
  default     = true
}

variable "system_node_labels" {
  type        = map(string)
  description = "Kubernetes labels of the system node pool, which add-on pods prefer. The compute/gke module labels it role=system."
  default     = { role = "system" }
}

################################################################################
# cert-manager
################################################################################

variable "cert_manager_enabled" {
  type        = bool
  description = "Install cert-manager, which issues and renews TLS certificates from Issuers such as Let's Encrypt."
  default     = false
}

variable "cert_manager_namespace" {
  type        = string
  description = "Namespace for cert-manager."
  default     = "cert-manager"
}

variable "cert_manager_chart_version" {
  type        = string
  description = "Version of the jetstack/cert-manager Helm chart."
  default     = "v1.21.2"
}

variable "cert_manager_helm_values" {
  type        = list(string)
  description = "Extra Helm values documents (YAML) for cert-manager, applied after the module's own."
  default     = []
}

################################################################################
# KEDA
################################################################################

variable "keda_enabled" {
  type        = bool
  description = "Install KEDA, which scales workloads on event sources such as Pub/Sub or queue depth."
  default     = false
}

variable "keda_namespace" {
  type        = string
  description = "Namespace for KEDA."
  default     = "keda"
}

variable "keda_chart_version" {
  type        = string
  description = "Version of the kedacore/keda Helm chart."
  default     = "2.20.2"
}

variable "keda_helm_values" {
  type        = list(string)
  description = "Extra Helm values documents (YAML) for KEDA, applied after the module's own."
  default     = []
}

################################################################################
# External Secrets Operator
################################################################################

variable "eso_enabled" {
  type        = bool
  description = "Install the External Secrets Operator with read access to Secret Manager through Workload Identity."
  default     = false
}

variable "eso_namespace" {
  type        = string
  description = "Namespace for the External Secrets Operator."
  default     = "external-secrets"
}

variable "eso_service_account" {
  type        = string
  description = "Kubernetes service account of the External Secrets controller, which Secret Manager access is granted to."
  default     = "external-secrets"
}

variable "eso_chart_version" {
  type        = string
  description = "Version of the external-secrets Helm chart."
  default     = "2.11.0"
}

variable "eso_secret_ids" {
  type        = list(string)
  description = "Secret Manager secrets (secret IDs, or projects/<p>/secrets/<id>) the controller may read. Empty grants every secret in the project."
  default     = []
}

variable "eso_allowed_namespaces" {
  type        = list(string)
  description = "Namespaces that may use the cluster secret store. Required when the store is created, because any pod in an allowed namespace can read any secret the controller can."
  default     = []
}

variable "eso_cluster_secret_store_creation_enabled" {
  type        = bool
  description = "Create a cluster-scoped Secret Manager ClusterSecretStore for the allowed namespaces."
  default     = true
}

variable "eso_cluster_secret_store_name" {
  type        = string
  description = "Name of the cluster-scoped Secret Manager store."
  default     = "ravion-gcp"
}

variable "eso_helm_values" {
  type        = list(string)
  description = "Extra Helm values documents (YAML) for the External Secrets Operator, applied after the module's own."
  default     = []
}
