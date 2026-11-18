################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the GKE cluster. Also prefixes the node service account."

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-40 lowercase letters, numbers, and hyphens, start with a letter, and end with a letter or number (GKE cluster name constraints)."
  }
}

variable "project_id" {
  type        = string
  description = "ID of the Google Cloud project the cluster is created in."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a Google Cloud project ID: 6-30 lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "region" {
  type        = string
  description = "Google Cloud region for the regional cluster, such as us-central1. The control plane and nodes are replicated across the region's zones."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region such as us-central1, not a zone."
  }
}

variable "node_locations" {
  type        = list(string)
  description = "Zones in the region that run nodes. Null uses every zone GKE picks for the region (usually three)."
  default     = null

  validation {
    condition     = var.node_locations == null || alltrue([for zone in coalesce(var.node_locations, []) : startswith(zone, "${var.region}-")])
    error_message = "Every node location must be a zone in the cluster region, such as us-central1-a."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to the cluster and its nodes' VMs and disks. Keys and values are lowercased and characters GCP labels do not allow become underscores."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "network" {
  type        = string
  description = "Name or self link of the VPC network the cluster runs in."
  default     = "default"
}

variable "subnetwork" {
  type        = string
  description = "Name or self link of the regional subnetwork for nodes. Must be in var.region."
  default     = "default"
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Existing secondary range on the subnetwork for pod IPs. Null lets GKE create one, sized by pods_ipv4_cidr_block."
  default     = null
}

variable "services_secondary_range_name" {
  type        = string
  description = "Existing secondary range on the subnetwork for Service IPs. Null lets GKE create one, sized by services_ipv4_cidr_block."
  default     = null
}

variable "pods_ipv4_cidr_block" {
  type        = string
  description = "Pod IP range GKE creates when pods_secondary_range_name is null: a CIDR such as 10.4.0.0/14, or a netmask such as /14. Null picks a /14 automatically."
  default     = null

  validation {
    condition     = var.pods_ipv4_cidr_block == null || var.pods_secondary_range_name == null
    error_message = "Set either pods_secondary_range_name or pods_ipv4_cidr_block, not both."
  }
}

variable "services_ipv4_cidr_block" {
  type        = string
  description = "Service IP range GKE creates when services_secondary_range_name is null: a CIDR such as 10.8.0.0/20, or a netmask such as /20. Null picks one automatically."
  default     = null

  validation {
    condition     = var.services_ipv4_cidr_block == null || var.services_secondary_range_name == null
    error_message = "Set either services_secondary_range_name or services_ipv4_cidr_block, not both."
  }
}

variable "dataplane_v2_enabled" {
  type        = bool
  description = "Use GKE Dataplane V2 (eBPF), which enforces Kubernetes NetworkPolicy. Changing it replaces the cluster."
  default     = true
}

variable "gateway_api_enabled" {
  type        = bool
  description = "Install the standard Kubernetes Gateway API CRDs and GKE's Gateway controller."
  default     = true
}

################################################################################
# Cluster
################################################################################

variable "release_channel" {
  type        = string
  description = "GKE release channel, which decides how quickly the control plane and nodes are upgraded."
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "The release_channel must be RAPID, REGULAR, STABLE, or EXTENDED."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Minimum control plane version, such as 1.34. Null uses the release channel's default. GKE still upgrades past it within the channel."
  default     = null
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "Fail any plan that would delete or replace the cluster until this is false."
  default     = true
}

variable "secrets_kms_key_name" {
  type        = string
  description = "Cloud KMS key (projects/<p>/locations/<region>/keyRings/<r>/cryptoKeys/<k>) for application-layer encryption of Kubernetes Secrets. The GKE service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it. Null keeps Google's default encryption at rest."
  default     = null

  validation {
    condition     = var.secrets_kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.secrets_kms_key_name))
    error_message = "The secrets_kms_key_name must be a Cloud KMS key name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

################################################################################
# Nodes
################################################################################

variable "node_service_account_creation_enabled" {
  type        = bool
  description = "Create a dedicated, least-privilege service account for nodes. Granting it its project roles needs roles/resourcemanager.projectIamAdmin on the identity running Terraform. When false, node_service_account_email is used."
  default     = true
}

variable "node_service_account_email" {
  type        = string
  description = "Existing service account for nodes when node_service_account_creation_enabled is false. It needs at least roles/container.defaultNodeServiceAccount."
  default     = null

  validation {
    condition     = var.node_service_account_creation_enabled || var.node_service_account_email != null
    error_message = "Set node_service_account_email when node_service_account_creation_enabled is false."
  }
}

variable "system_node_pool" {
  type = object({
    capacity_type = optional(string, "ON_DEMAND")
    machine_type  = optional(string, "e2-standard-2")
    min_nodes     = optional(number, 2)
    max_nodes     = optional(number, 3)
    disk_size_gb  = optional(number)
    disk_type     = optional(string, "pd-balanced")
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  })
  description = "Always-on node pool for cluster add-ons. Node counts are totals across zones. Nodes are labelled role=system."
  default     = {}

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.system_node_pool.capacity_type)
    error_message = "system_node_pool.capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = var.system_node_pool.min_nodes >= 1 && var.system_node_pool.max_nodes >= var.system_node_pool.min_nodes
    error_message = "system_node_pool needs min_nodes >= 1 and max_nodes >= min_nodes."
  }

  validation {
    condition     = alltrue([for taint in var.system_node_pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    error_message = "Taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "node_pools" {
  type = map(object({
    capacity_type = optional(string, "ON_DEMAND")
    machine_type  = optional(string, "e2-standard-4")
    min_nodes     = optional(number, 0)
    max_nodes     = optional(number, 3)
    disk_size_gb  = optional(number)
    disk_type     = optional(string, "pd-balanced")
    labels        = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  description = "Additional autoscaled node pools, keyed by a name prefix of 1-13 characters. Node counts are totals across zones. A change GKE can only make by recreating the pool brings up the new pool before the old one is removed."
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.node_pools) : can(regex("^[a-z]([-a-z0-9]{0,11}[a-z0-9])?$", key)) && key != "system"])
    error_message = "Node pool keys must be 1-13 lowercase letters, numbers, and hyphens, start with a letter, and must not be \"system\"."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : contains(["ON_DEMAND", "SPOT"], pool.capacity_type)])
    error_message = "Node pool capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : pool.min_nodes >= 0 && pool.max_nodes >= 1 && pool.max_nodes >= pool.min_nodes])
    error_message = "Node pools need min_nodes >= 0, max_nodes >= 1, and max_nodes >= min_nodes."
  }

  validation {
    condition     = alltrue(flatten([for pool in values(var.node_pools) : [for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)]]))
    error_message = "Taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "node_auto_provisioning_enabled" {
  type        = bool
  description = "Let GKE create and delete node pools sized for pending pods that fit no existing pool, up to the CPU and memory limits below."
  default     = true
}

variable "node_auto_provisioning_cpu_limit" {
  type        = number
  description = "Most vCPUs the whole cluster may have when node auto-provisioning is on, counting every node pool."
  default     = 100

  validation {
    condition     = var.node_auto_provisioning_cpu_limit >= 1
    error_message = "node_auto_provisioning_cpu_limit must be at least 1."
  }
}

variable "node_auto_provisioning_memory_limit_gb" {
  type        = number
  description = "Most memory, in GB, the whole cluster may have when node auto-provisioning is on, counting every node pool."
  default     = 400

  validation {
    condition     = var.node_auto_provisioning_memory_limit_gb >= 1
    error_message = "node_auto_provisioning_memory_limit_gb must be at least 1."
  }
}

variable "autoscaling_profile" {
  type        = string
  description = "Cluster autoscaler profile. OPTIMIZE_UTILIZATION removes underused nodes sooner at the cost of more pod rescheduling."
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "The autoscaling_profile must be BALANCED or OPTIMIZE_UTILIZATION."
  }
}

################################################################################
# Control plane endpoint
################################################################################

variable "dns_endpoint_enabled" {
  type        = bool
  description = "Allow requests to the control plane's DNS-based endpoint from outside the VPC. Every request is still authorized by IAM, and Ravion runners use it to reach the API without a network path into the VPC."
  default     = true
}

variable "ip_endpoint_public_access_enabled" {
  type        = bool
  description = "Expose the control plane's public IP endpoint. When false, the IP-based endpoint is reachable only from inside the VPC."
  default     = false
}

variable "master_authorized_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach the IP-based control plane endpoints. Empty allows only the VPC (and nothing from the internet)."
  default     = []

  validation {
    condition     = alltrue([for cidr_block in var.master_authorized_cidr_blocks : can(cidrhost(cidr_block, 0))])
    error_message = "Every master_authorized_cidr_blocks entry must be a valid IPv4 CIDR block."
  }
}

################################################################################
# Access
################################################################################

variable "ravion_runner_cluster_admin_enabled" {
  type        = bool
  description = "Grant the Ravion runner service account roles/container.admin, so pipelines (such as the GKE Add-ons module) can manage Kubernetes objects. GKE has no per-cluster IAM, so the role covers every cluster in the project."
  default     = true
}

variable "ravion_runner_service_account_email" {
  type        = string
  description = "Ravion runner service account. Null uses ravion-runner@<project_id>.iam.gserviceaccount.com, the account Ravion's GCP setup creates."
  default     = null
}

variable "access_members" {
  type = map(object({
    member = string
    role   = optional(string, "roles/container.developer")
  }))
  description = "IAM principals granted a GKE role on the project, such as group:platform@example.com with roles/container.admin."
  default     = {}

  validation {
    condition     = alltrue([for entry in values(var.access_members) : contains(["roles/container.viewer", "roles/container.developer", "roles/container.admin", "roles/container.clusterViewer"], entry.role)])
    error_message = "Access member roles must be roles/container.viewer, roles/container.developer, roles/container.admin, or roles/container.clusterViewer."
  }

  validation {
    condition     = alltrue([for entry in values(var.access_members) : can(regex("^(user|group|serviceAccount|domain|principal|principalSet):.+", entry.member))])
    error_message = "Access members must be IAM principals such as user:alice@example.com, group:platform@example.com, or serviceAccount:ci@project.iam.gserviceaccount.com."
  }
}

################################################################################
# Observability
################################################################################

variable "logging_components" {
  type        = list(string)
  description = "Components whose logs GKE sends to Cloud Logging. An empty list turns logging off."
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  validation {
    condition = alltrue([for component in var.logging_components : contains([
      "SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER", "KCP_CONNECTION", "KCP_SSHD", "KCP_HPA",
    ], component)])
    error_message = "Logging components must be SYSTEM_COMPONENTS, WORKLOADS, APISERVER, CONTROLLER_MANAGER, SCHEDULER, KCP_CONNECTION, KCP_SSHD, or KCP_HPA."
  }

  validation {
    condition     = length(var.logging_components) == 0 || contains(var.logging_components, "SYSTEM_COMPONENTS")
    error_message = "GKE requires SYSTEM_COMPONENTS whenever any logging component is enabled."
  }
}

variable "managed_prometheus_enabled" {
  type        = bool
  description = "Collect metrics with Google Cloud Managed Service for Prometheus."
  default     = true
}
