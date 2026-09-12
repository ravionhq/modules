################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this Fargate profile attaches to."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster_name must not be empty."
  }
}

variable "name" {
  type        = string
  description = "Name of the Fargate profile."

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
  description = "Private subnet IDs Fargate pods are launched in. Public subnets are not allowed by EKS Fargate."

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
# Selectors
################################################################################

variable "selectors" {
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  description = <<-EOT
    Pod selectors that determine which pods run on this Fargate profile. A pod
    matches when its namespace and labels both match a selector. At least one
    selector is required.

    Example:
    ```
    selectors = [
      { namespace = "kube-system" },
      { namespace = "default", labels = { tier = "edge" } },
    ]
    ```
  EOT

  validation {
    condition     = length(var.selectors) >= 1
    error_message = "At least one selector is required."
  }
}

################################################################################
# IAM
################################################################################

variable "pod_execution_role_arn" {
  type        = string
  description = "Existing pod execution role ARN. When null, the module creates one."
  default     = null

  validation {
    condition     = var.pod_execution_role_arn == null || trimspace(var.pod_execution_role_arn) == "" || can(regex("^arn:aws[a-zA-Z-]*:iam::", var.pod_execution_role_arn))
    error_message = "The pod_execution_role_arn must be a valid IAM role ARN."
  }
}
