################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install add-ons on."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster_name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Add-ons
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
