################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the EKS cluster. Used as the cluster name and as the prefix for related resources (log group, KMS alias, role names)."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.name))
    error_message = "The name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the EKS cluster. Format: 'X.YY' (e.g. '1.31'). When null, AWS uses the latest supported version."
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The kubernetes_version must be in 'MAJOR.MINOR' form (e.g. '1.31')."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, the resource cannot be deleted via the AWS API until this is set to false. Safe-by-default."
  default     = true
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the cluster will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EKS-managed control plane ENIs. Typically private subnets in at least two availability zones."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs (in different availability zones) are required for EKS control plane high availability."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "endpoint_public_access_enabled" {
  type        = bool
  description = "Whether the EKS API server endpoint is reachable from the public internet."
  default     = false
}

variable "endpoint_private_access_enabled" {
  type        = bool
  description = "Whether the EKS API server endpoint is reachable from inside the VPC."
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public EKS API server endpoint. Only applies when endpoint_public_access_enabled is true."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "All public_access_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  description = "Optional CIDR block from which Kubernetes service IPs are assigned. When null, EKS picks a default."
  default     = null

  validation {
    condition     = var.service_ipv4_cidr == null || can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "The service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "ip_family" {
  type        = string
  description = "IP family for the cluster. Either 'ipv4' or 'ipv6'."
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "The ip_family must be 'ipv4' or 'ipv6'."
  }
}

variable "cluster_security_group_additional_cidr_ingress_rules" {
  type = list(object({
    description = optional(string)
    from_port   = number
    to_port     = number
    ip_protocol = string
    cidr_ipv4   = string
  }))
  description = "Extra ingress rules to attach to the EKS-managed cluster security group, sourced by IPv4 CIDR."
  default     = []
}

variable "cluster_security_group_additional_referenced_security_group_ingress_rules" {
  type = list(object({
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = string
    referenced_security_group_id = string
  }))
  description = "Extra ingress rules to attach to the EKS-managed cluster security group, sourced by another security group."
  default     = []
}

################################################################################
# Access
################################################################################

variable "bootstrap_cluster_creator_admin_permissions_enabled" {
  type        = bool
  description = "Whether to grant the IAM principal that creates the cluster the EKS cluster admin permissions automatically. AWS recommends managing access via aws_eks_access_entry instead."
  default     = true
}

variable "oidc_provider_creation_enabled" {
  type        = bool
  description = "Create an IAM OIDC provider for workloads using IRSA. EKS Pod Identity does not require it. Set true before upgrading a cluster whose workloads still use IRSA."
  default     = false
  nullable    = false
}

variable "vpc_resource_controller_policy_enabled" {
  type        = bool
  description = "Attach AmazonEKSVPCResourceController to the cluster role for Windows networking or security groups for pods. Not required for ordinary Linux pod networking or multi-AZ placement."
  default     = false
  nullable    = false
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    user_name         = optional(string)
    policy_associations = optional(map(object({
      policy_arn              = string
      access_scope_type       = optional(string, "cluster")
      access_scope_namespaces = optional(list(string), [])
    })), {})
  }))
  description = <<-EOT
    Map of EKS access entries to create. Map keys are arbitrary stable identifiers.

    Example:
    ```
    access_entries = {
      "platform-admins" = {
        principal_arn = "arn:aws:iam::123456789012:role/PlatformAdmins"
        policy_associations = {
          "cluster-admin" = {
            policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope_type = "cluster"
          }
        }
      }
    }
    ```
  EOT
  default     = {}

  validation {
    condition     = alltrue([for e in var.access_entries : contains(["STANDARD", "EC2_LINUX", "EC2_WINDOWS", "FARGATE_LINUX"], e.type)])
    error_message = "Each access_entries.*.type must be 'STANDARD', 'EC2_LINUX', 'EC2_WINDOWS', or 'FARGATE_LINUX'."
  }

  validation {
    condition = alltrue([
      for e in var.access_entries : alltrue([
        for a in values(e.policy_associations) : contains(["cluster", "namespace"], a.access_scope_type)
      ])
    ])
    error_message = "Each access_entries.*.policy_associations.*.access_scope_type must be 'cluster' or 'namespace'."
  }

  validation {
    condition = alltrue([
      for e in var.access_entries : alltrue([
        for a in values(e.policy_associations) :
        a.access_scope_type != "namespace" || length(a.access_scope_namespaces) >= 1
      ])
    ])
    error_message = "Each namespace-scoped policy association must list at least one namespace in access_scope_namespaces."
  }
}

################################################################################
# Logging
################################################################################

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Which control plane log types to ship to CloudWatch Logs. Set to [] to disable cluster logging entirely."
  default     = ["api", "audit", "authenticator"]

  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "Each enabled_cluster_log_types entry must be one of: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_log_retention_in_days" {
  type        = number
  description = "Retention (days) for the EKS control plane CloudWatch log group. Ignored when enabled_cluster_log_types is empty."
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653],
      var.cluster_log_retention_in_days,
    )
    error_message = "The cluster_log_retention_in_days must be a value supported by CloudWatch Logs (e.g. 1, 3, 7, 14, 30, 90, 365, 0 for never expire)."
  }
}

################################################################################
# Encryption
################################################################################

variable "secrets_encryption_enabled" {
  type        = bool
  description = "Enable envelope encryption for Kubernetes secrets using KMS. When secrets_kms_key_arn is null, a new symmetric key is created via the security/kms module."
  default     = true
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "ARN of an existing KMS key to use for Kubernetes secrets envelope encryption. When null and secrets_encryption_enabled is true, the module creates one."
  default     = null

  validation {
    condition     = var.secrets_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.secrets_kms_key_arn))
    error_message = "The secrets_kms_key_arn must be a valid KMS key ARN."
  }
}

################################################################################
# Add-ons
################################################################################

variable "vpc_cni_addon_version" {
  type        = string
  description = "Pinned version for the vpc-cni add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "vpc_cni_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for vpc-cni. See AWS docs for available keys."
  default     = null
}

variable "kube_proxy_addon_version" {
  type        = string
  description = "Pinned version for the kube-proxy add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "kube_proxy_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for kube-proxy."
  default     = null
}

variable "pod_identity_agent_enabled" {
  type        = bool
  description = "Install the eks-pod-identity-agent add-on. Required for any Pod Identity associations to take effect at runtime."
  default     = true
}

variable "pod_identity_agent_addon_version" {
  type        = string
  description = "Pinned version for the eks-pod-identity-agent add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "aws_load_balancer_controller_pod_identity_creation_enabled" {
  type        = bool
  description = "Create an IAM role and Pod Identity association for the AWS Load Balancer Controller (Helm-installed by the consumer)."
  default     = true
}

variable "aws_load_balancer_controller_namespace" {
  type        = string
  description = "Kubernetes namespace where the AWS Load Balancer Controller's service account lives."
  default     = "kube-system"
}

variable "aws_load_balancer_controller_service_account" {
  type        = string
  description = "Kubernetes service account name used by the AWS Load Balancer Controller."
  default     = "aws-load-balancer-controller"
}

variable "pod_identity_associations" {
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
  description = "Additional Pod Identity associations to create on the cluster, keyed by a stable identifier."
  default     = {}
}
