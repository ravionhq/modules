################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the workload. Names the Artifact Registry repository and the reserved Gateway address unless overridden."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,51}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-53 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
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
  description = "Region of the regional cluster, such as us-central1. Regional resources (repository, internal address) are created here."
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to every labelable resource. Keys and values are normalized to GCP label rules."
  default     = {}
}

################################################################################
# Cluster and release identity
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster the workload runs on. Required when workload_release_cleanup_enabled is true."
  default     = null
}

variable "dns_endpoint" {
  type        = string
  description = "DNS-based control plane endpoint of the cluster (rvn-gke-cluster's dns_endpoint output), reached with the runner's Google access token. Required when workload_release_cleanup_enabled is true."
  default     = null
}

variable "release_name" {
  type        = string
  description = "Name of the Helm release Ravion installs for this workload."
  default     = null

  validation {
    condition     = var.release_name == null || can(regex("^[a-z0-9]([a-z0-9-]{0,51}[a-z0-9])?$", var.release_name))
    error_message = "release_name must be 1-53 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "release_namespace" {
  type        = string
  description = "Kubernetes namespace the Helm release is installed into. The namespace itself is never removed; it may be shared."
  default     = null

  validation {
    condition     = var.release_namespace == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.release_namespace))
    error_message = "release_namespace must be 1-63 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "kubernetes_service_enabled" {
  type        = bool
  description = "Whether the workload's chart renders a Kubernetes Service named after the release. Enables the service_host, service_port and service_url outputs. Only the web workload sets it."
  default     = false
}

variable "container_port" {
  type        = number
  description = "Port the application container listens on, which the chart's Service also listens on."
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "The container_port must be between 1 and 65535."
  }
}

################################################################################
# Load balancer (GKE Gateway)
################################################################################

variable "load_balancer_scheme" {
  type        = string
  description = "external reserves a global address for a global external Application Load Balancer Gateway; internal reserves an internal address for a regional internal one. Null for a cluster-only workload."
  default     = null

  validation {
    condition     = var.load_balancer_scheme == null || contains(["external", "internal"], coalesce(var.load_balancer_scheme, "external"))
    error_message = "The load_balancer_scheme must be external, internal, or null."
  }
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork the internal Gateway address is reserved in, normally the cluster's subnetwork. Required when load_balancer_scheme is internal."
  default     = null
}

variable "hostnames" {
  type        = list(string)
  description = "Hostnames the workload's HTTPRoute matches. The first one without a wildcard becomes the host of load_balancer_url."
  default     = []
}

variable "gateway_certificate_map_name" {
  type        = string
  description = "Certificate Manager certificate map the external Gateway serves HTTPS with. Setting it, or gateway_pre_shared_certificate_names, makes load_balancer_url https."
  default     = null
}

variable "gateway_pre_shared_certificate_names" {
  type        = list(string)
  description = "Compute Engine SSL certificates (global for external, regional for internal) the Gateway serves HTTPS with."
  default     = []
  nullable    = false
}

################################################################################
# Artifact Registry Repository
################################################################################

variable "artifact_registry_repository_creation_enabled" {
  type        = bool
  description = "Create a Docker Artifact Registry repository for this workload's images. The module definitions set it for the Dockerfile and Railpack build sources."
  default     = false
}

variable "artifact_registry_repository_id" {
  type        = string
  description = "Repository ID. Defaults to var.name."
  default     = null

  validation {
    condition     = var.artifact_registry_repository_id == null || can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.artifact_registry_repository_id))
    error_message = "The artifact_registry_repository_id must be 1-63 lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "artifact_registry_immutable_tags_enabled" {
  type        = bool
  description = "Reject pushes that move an existing tag. Ravion builds push a moving build-type tag, so leave this off for built workloads."
  default     = false
}

variable "artifact_registry_vulnerability_scanning_enabled" {
  type        = bool
  description = "Scan pushed images when the Container Scanning API is enabled on the project."
  default     = true
}

variable "artifact_registry_cleanup_policies_enabled" {
  type        = bool
  description = "Delete all but the most recent artifact_registry_max_image_count image versions."
  default     = true
}

variable "artifact_registry_max_image_count" {
  type        = number
  description = "Image versions the cleanup policy keeps."
  default     = 100

  validation {
    condition     = var.artifact_registry_max_image_count >= 1
    error_message = "The artifact_registry_max_image_count must be at least 1."
  }
}

################################################################################
# Workload Identity
################################################################################

variable "workload_identity_pool" {
  type        = string
  description = "Workload Identity pool of the cluster (rvn-gke-cluster's workload_identity_pool output). Defaults to <project_id>.svc.id.goog."
  default     = null
}

variable "workload_identity_service_account_name" {
  type        = string
  description = "Kubernetes service account in release_namespace allowed to act as the workload's Google service account. Defaults to release_name, which is what the rvn-gke-* charts name it."
  default     = null
}

variable "workload_identity_project_roles" {
  type        = list(string)
  description = "IAM roles granted on the project to a Google service account this stack creates for the workload, which the release's Kubernetes service account acts as through Workload Identity, such as roles/storage.objectViewer. Empty creates and grants nothing."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for role in var.workload_identity_project_roles : can(regex("^(roles/|projects/[^/]+/roles/|organizations/[0-9]+/roles/)", role))])
    error_message = "Each workload_identity_project_roles entry must be a role name such as roles/storage.objectViewer or projects/<project>/roles/<custom role>."
  }

  validation {
    condition     = length(var.workload_identity_project_roles) == 0 || var.release_namespace != null
    error_message = "workload_identity_project_roles requires release_namespace: the workloadIdentityUser binding names a Kubernetes service account in a namespace."
  }

  validation {
    condition     = length(var.workload_identity_project_roles) == 0 || var.cluster_name != null
    error_message = "workload_identity_project_roles requires cluster_name: the Google service account ID is derived from the cluster, so stacks on different clusters do not share one."
  }
}

################################################################################
# Workload release teardown
################################################################################

variable "workload_release_cleanup_enabled" {
  type        = bool
  description = "Uninstall the workload's Helm release when this stack is destroyed. Requires cluster_name, dns_endpoint, release_name and release_namespace."
  default     = false
}

variable "workload_release_helm_version" {
  type        = string
  description = "Helm version downloaded for the uninstall when no `helm` binary is on the PATH of the machine running the destroy."
  default     = "v4.2.4"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.workload_release_helm_version))
    error_message = "workload_release_helm_version must look like vX.Y.Z."
  }
}

variable "workload_release_uninstall_timeout" {
  type        = string
  description = "How long `helm uninstall --wait` waits for the workload's objects to be gone before the destroy fails."
  default     = "10m"
}
