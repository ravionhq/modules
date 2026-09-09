################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the EKS cluster. Used as the cluster name and as the prefix for related resources."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.name))
    error_message = "The name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
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
  description = "Subnet IDs for the EKS-managed control plane ENIs. Also used as the default node / Fargate placement when node_subnet_ids is null. Typically private subnets in at least two availability zones."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs (in different availability zones) are required for EKS control plane high availability."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the system node group, additional node groups, and Fargate profiles when they do not override placement. Defaults to subnet_ids."
  default     = null

  validation {
    condition = var.node_subnet_ids == null || (
      length(var.node_subnet_ids) >= 1 &&
      alltrue([for s in var.node_subnet_ids : can(regex("^subnet-", s))])
    )
    error_message = "When set, node_subnet_ids must contain at least one subnet ID starting with 'subnet-'."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs in the cluster VPC. Not used by the cluster itself; exposed as an output so dependent modules (such as compute/eks/addons shared load balancers) can place internet-facing resources."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# Cluster
################################################################################

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the EKS cluster. Format: 'X.YY' (e.g. '1.31'). When null, AWS uses the latest supported version."
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The kubernetes_version must be in 'MAJOR.MINOR' form (e.g. '1.31')."
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

variable "ravion_runner_role_creation_enabled" {
  type        = bool
  description = "Create the stable provisioning Runner IAM role with an EKS cluster-admin access entry. Independent of runtime read/admin access roles."
  default     = true
}

variable "ravion_runner_role_trusted_principal_arns" {
  type        = list(string)
  description = "IAM principal ARN patterns allowed to assume the provisioning Runner role (aws:PrincipalArn ArnLike condition). Empty means any principal in this account that holds sts:AssumeRole on the role's ARN. Does not affect runtime read/admin trust."
  default     = []

  validation {
    condition     = alltrue([for arn in var.ravion_runner_role_trusted_principal_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:(role/.+|user/.+|root)$", arn))])
    error_message = "Use IAM role/user ARN patterns or account root ARNs with an explicit 12-digit account ID."
  }
}

variable "ravion_integration_role_arn" {
  type        = string
  description = "Exact Ravion integration IAM role ARN in the cluster's AWS account and partition. Supplied by the platform aws.account.integration_role_arn context; required for read and deploy role trust."
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]{1,64}$", var.ravion_integration_role_arn))
    error_message = "Supply an exact IAM role ARN, optionally with a role path; root, users, sessions, wildcards, and empty values are not allowed."
  }

  validation {
    condition     = can(regex("^arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/", var.ravion_integration_role_arn))
    error_message = "The Ravion integration role must belong to the cluster provider's AWS account and partition."
  }
}

variable "ravion_runner_security_group_creation_enabled" {
  type        = bool
  description = "Create a Ravion Runner security group in the cluster VPC and allow it to reach the Kubernetes API endpoint (443) on the EKS-managed cluster security group. Attach the security group to the Ravion execution environment used by this module."
  default     = true
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

variable "bootstrap_cluster_creator_admin_permissions_enabled" {
  type        = bool
  description = "Whether to grant the IAM principal that creates the cluster the EKS cluster admin permissions automatically."
  default     = true
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
  description = "Map of EKS access entries to create. Map keys are arbitrary stable identifiers."
  default     = {}
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Which control plane log types to ship to CloudWatch Logs. Set to [] to disable cluster logging entirely."
  default     = ["api", "audit", "authenticator"]
}

variable "cluster_log_retention_in_days" {
  type        = number
  description = "Retention (days) for the EKS control plane CloudWatch log group."
  default     = 30
}

variable "secrets_encryption_enabled" {
  type        = bool
  description = "Enable envelope encryption for Kubernetes secrets using KMS."
  default     = true
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "ARN of an existing KMS key for Kubernetes secrets. When null and secrets_encryption_enabled is true, the cluster module creates one."
  default     = null
}

variable "vpc_cni_addon_version" {
  type        = string
  description = "Pinned version for the vpc-cni add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "vpc_cni_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for vpc-cni."
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
  description = "Install the eks-pod-identity-agent add-on."
  default     = true
}

variable "pod_identity_agent_addon_version" {
  type        = string
  description = "Pinned version for the eks-pod-identity-agent add-on."
  default     = null
}

variable "aws_load_balancer_controller_pod_identity_creation_enabled" {
  type        = bool
  description = "Create an IAM role and Pod Identity association for the AWS Load Balancer Controller."
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
  description = "Additional Pod Identity associations to create on the cluster."
  default     = {}
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, the cluster cannot be deleted via the AWS API until this is set to false."
  default     = true
}

################################################################################
# Node Groups
################################################################################

variable "system_node_group" {
  type = object({
    name                         = optional(string, "system")
    capacity_type                = optional(string, "ON_DEMAND")
    instance_types               = optional(list(string), ["t3.medium"])
    ami_type                     = optional(string, "AL2023_x86_64_STANDARD")
    kubernetes_version           = optional(string)
    min_size                     = optional(number, 2)
    max_size                     = optional(number, 4)
    max_unavailable              = optional(number)
    max_unavailable_percentage   = optional(number, 33)
    version_force_update_enabled = optional(bool, false)
    labels                       = optional(map(string), { role = "system" })
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    disk_size                                = optional(number)
    disk_type                                = optional(string)
    disk_iops                                = optional(number)
    disk_throughput                          = optional(number)
    ebs_kms_key_arn                          = optional(string)
    user_data                                = optional(string)
    security_group_ids                       = optional(list(string), [])
    detailed_monitoring_enabled              = optional(bool, false)
    metadata_http_tokens                     = optional(string, "required")
    metadata_http_put_response_hop_limit     = optional(number, 2)
    node_role_arn                            = optional(string)
    node_role_additional_managed_policy_arns = optional(list(string), [])
    node_role_additional_inline_policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  description = "Configuration for the required default managed node group that provides compute for cluster components, add-ons, and workloads without stricter placement."
  default     = {}
}

variable "node_groups" {
  type = map(object({
    subnet_ids                   = optional(list(string))
    capacity_type                = optional(string, "ON_DEMAND")
    instance_types               = optional(list(string), ["t3.medium"])
    ami_type                     = optional(string, "AL2023_x86_64_STANDARD")
    kubernetes_version           = optional(string)
    min_size                     = optional(number, 1)
    max_size                     = optional(number, 3)
    max_unavailable              = optional(number)
    max_unavailable_percentage   = optional(number, 33)
    version_force_update_enabled = optional(bool, false)
    labels                       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    disk_size                                = optional(number)
    disk_type                                = optional(string)
    disk_iops                                = optional(number)
    disk_throughput                          = optional(number)
    ebs_kms_key_arn                          = optional(string)
    user_data                                = optional(string)
    security_group_ids                       = optional(list(string), [])
    detailed_monitoring_enabled              = optional(bool, false)
    metadata_http_tokens                     = optional(string, "required")
    metadata_http_put_response_hop_limit     = optional(number, 2)
    node_role_arn                            = optional(string)
    node_role_additional_managed_policy_arns = optional(list(string), [])
    node_role_additional_inline_policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  }))
  description = "Optional additional managed node groups keyed by node group name. Placement defaults to node_subnet_ids (or subnet_ids)."
  default     = {}
}

################################################################################
# Post-compute Add-ons
################################################################################

variable "coredns_addon_version" {
  type        = string
  description = "Pinned version for the coredns add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "coredns_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for coredns."
  default     = null
}

################################################################################
# Fargate
################################################################################

variable "fargate_profiles" {
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
    subnet_ids             = optional(list(string))
    pod_execution_role_arn = optional(string)
  }))
  description = "Optional Fargate profiles keyed by profile name. subnet_ids defaults to node_subnet_ids (or subnet_ids)."
  default     = {}

  validation {
    condition = alltrue([
      for p in values(var.fargate_profiles) : length(p.selectors) >= 1
    ])
    error_message = "Each fargate_profiles entry must include at least one selector."
  }
}
variable "ravion_access_relay_instance_type" {
  type        = string
  description = "Dedicated ARM connection relay size. t4g.micro provides practical memory headroom for SSM; t4g.nano minimizes cost."
  default     = "t4g.micro"
  validation {
    condition     = contains(["t4g.nano", "t4g.micro"], var.ravion_access_relay_instance_type)
    error_message = "Use t4g.nano or t4g.micro (ARM64)."
  }
}

variable "ravion_access_relay_subnet_id" {
  type        = string
  description = "Private subnet for the dedicated relay; defaults to the first cluster subnet. Requires NAT or SSM interface endpoints."
  default     = null
}

variable "ravion_access_ssm_egress_cidrs" {
  type        = list(string)
  description = "IPv4 HTTPS destinations for SSM. Restrict to interface endpoint CIDRs when available; default supports NAT."
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.ravion_access_ssm_egress_cidrs) > 0 && alltrue([for cidr in var.ravion_access_ssm_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply at least one valid IPv4 CIDR."
  }
}
