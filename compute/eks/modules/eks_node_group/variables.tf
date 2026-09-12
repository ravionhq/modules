################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this node group joins."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster_name must not be empty."
  }
}

variable "name" {
  type        = string
  description = "Name of the managed node group. Must be unique within the cluster."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-_]{0,62}$", var.name))
    error_message = "The name must be 1-63 characters, alphanumerics with hyphens or underscores, starting with an alphanumeric."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "partition" {
  type        = string
  description = "AWS partition (e.g. 'aws', 'aws-us-gov') used to build managed policy ARNs. Pass this from the calling module when this module is instantiated with depends_on, so policy ARNs are known at plan time; when null, it is resolved via a data source."
  default     = null

  validation {
    condition     = var.partition == null || can(regex("^aws", var.partition))
    error_message = "The partition must be a valid AWS partition name (e.g. 'aws', 'aws-us-gov', 'aws-cn')."
  }
}

################################################################################
# Placement
################################################################################

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs to launch nodes into. Typically private subnets."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# Capacity / Scaling
################################################################################

variable "capacity_type" {
  type        = string
  description = "Capacity type for instances: ON_DEMAND, SPOT, or CAPACITY_BLOCK."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT", "CAPACITY_BLOCK"], var.capacity_type)
    error_message = "The capacity_type must be ON_DEMAND, SPOT, or CAPACITY_BLOCK."
  }
}

variable "instance_types" {
  type        = list(string)
  description = "Instance types EKS will choose from. For SPOT, supply several similar shapes."
  default     = ["t3.medium"]

  validation {
    condition     = length(var.instance_types) >= 1
    error_message = "At least one instance type is required."
  }
}

variable "ami_type" {
  type        = string
  description = "AMI type managed by EKS. AL2023_x86_64_STANDARD is the default for new clusters."
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains(
      [
        "AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64",
        "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD",
        "AL2023_x86_64_NEURON", "AL2023_x86_64_NVIDIA",
        "AL2023_ARM_64_NVIDIA",
        "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64",
        "BOTTLEROCKET_ARM_64_NVIDIA", "BOTTLEROCKET_x86_64_NVIDIA",
        "WINDOWS_CORE_2019_x86_64", "WINDOWS_FULL_2019_x86_64",
        "WINDOWS_CORE_2022_x86_64", "WINDOWS_FULL_2022_x86_64",
        "CUSTOM",
      ],
      var.ami_type,
    )
    error_message = "The ami_type must be a value supported by aws_eks_node_group."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the node group. When null, the cluster's version is used."
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The kubernetes_version must be in 'MAJOR.MINOR' form (e.g. '1.31')."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes."
  default     = 1

  validation {
    condition     = var.min_size >= 0
    error_message = "The min_size must be 0 or greater."
  }
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes at creation. Subsequent changes by an autoscaler are ignored to avoid drift."
  default     = 1

  validation {
    condition     = var.desired_size >= 0
    error_message = "The desired_size must be 0 or greater."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes."
  default     = 3

  validation {
    condition     = var.max_size >= 1
    error_message = "The max_size must be at least 1."
  }
}

variable "max_unavailable" {
  type        = number
  description = "Max number of nodes unavailable during a node group update. Mutually exclusive with max_unavailable_percentage."
  default     = null

  validation {
    condition     = var.max_unavailable == null || var.max_unavailable >= 1
    error_message = "The max_unavailable must be at least 1 when set."
  }
}

variable "max_unavailable_percentage" {
  type        = number
  description = "Max percentage of nodes unavailable during a node group update. Mutually exclusive with max_unavailable."
  default     = 33

  validation {
    condition     = var.max_unavailable_percentage == null || (var.max_unavailable_percentage >= 1 && var.max_unavailable_percentage <= 100)
    error_message = "The max_unavailable_percentage must be between 1 and 100 when set."
  }
}

variable "version_force_update_enabled" {
  type        = bool
  description = "Allow EKS to force-evict pods (ignore PDBs) during a node group version update."
  default     = false
}

################################################################################
# Workload Hints
################################################################################

variable "labels" {
  type        = map(string)
  description = "Kubernetes labels applied to nodes in this group."
  default     = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  description = "Kubernetes taints applied to nodes in this group."
  default     = []

  validation {
    condition     = alltrue([for t in var.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)])
    error_message = "Each taint effect must be NO_SCHEDULE, NO_EXECUTE, or PREFER_NO_SCHEDULE."
  }
}

################################################################################
# Launch Template Customization
#
# Setting any of these triggers creation of a launch template. Otherwise the
# node group runs on the EKS-supplied default launch template.
################################################################################

variable "disk_size" {
  type        = number
  description = "Root volume size in GB."
  default     = null

  validation {
    condition     = var.disk_size == null || (var.disk_size >= 8 && var.disk_size <= 16384)
    error_message = "The disk_size must be between 8 and 16384 GB when set."
  }
}

variable "disk_type" {
  type        = string
  description = "Root volume type."
  default     = null

  validation {
    condition     = var.disk_type == null || contains(["gp2", "gp3", "io1", "io2"], var.disk_type)
    error_message = "The disk_type must be 'gp2', 'gp3', 'io1', or 'io2' when set."
  }
}

variable "disk_iops" {
  type        = number
  description = "Root volume IOPS (gp3/io1/io2 only)."
  default     = null
}

variable "disk_throughput" {
  type        = number
  description = "Root volume throughput in MB/s (gp3 only)."
  default     = null
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for root EBS volume encryption. When null, defaults to the AWS-managed EBS key."
  default     = null

  validation {
    condition     = var.ebs_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.ebs_kms_key_arn))
    error_message = "The ebs_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "user_data" {
  type        = string
  description = "Custom user data placed verbatim in the launch template (module base64-encodes it). EKS merges its own node bootstrap user data with this, so the value must use the format the ami_type expects: MIME multi-part for AL2/AL2023, TOML for Bottlerocket, PowerShell for Windows. See the module README."
  default     = null
}

variable "security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs attached to the node ENIs."
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "detailed_monitoring_enabled" {
  type        = bool
  description = "Enable EC2 detailed (1-minute) monitoring on instances."
  default     = false
}

variable "metadata_http_tokens" {
  type        = string
  description = "IMDS http_tokens setting. 'required' enforces IMDSv2."
  default     = "required"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "The metadata_http_tokens must be 'required' or 'optional'."
  }
}

variable "metadata_http_put_response_hop_limit" {
  type        = number
  description = "IMDS hop limit. AWS recommends 2 to allow containerized workloads to reach IMDS."
  default     = 2

  validation {
    condition     = var.metadata_http_put_response_hop_limit >= 1 && var.metadata_http_put_response_hop_limit <= 64
    error_message = "The metadata_http_put_response_hop_limit must be between 1 and 64."
  }
}

################################################################################
# IAM
################################################################################

variable "node_role_arn" {
  type        = string
  description = "Existing IAM role ARN to use as the node role. When null, the module creates one."
  default     = null

  validation {
    condition     = var.node_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::", var.node_role_arn))
    error_message = "The node_role_arn must be a valid IAM role ARN."
  }
}

variable "node_role_additional_managed_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the module-created node role. Ignored if node_role_arn is supplied."
  default     = []
}

variable "node_role_additional_inline_policy_statements" {
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = "Extra inline policy statements added to the module-created node role. Ignored if node_role_arn is supplied."
  default     = []
}
