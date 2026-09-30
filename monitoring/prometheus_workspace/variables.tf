################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Alias of the workspace, and the value of its Name tag."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$", var.name))
    error_message = "The name must be 1-100 letters, digits, underscores, periods or hyphens, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

################################################################################
# Workspace
################################################################################

variable "retention_period_in_days" {
  type        = number
  description = "Number of days the workspace keeps samples before deleting them."
  default     = 150

  validation {
    condition     = var.retention_period_in_days >= 1 && var.retention_period_in_days <= 1095 && floor(var.retention_period_in_days) == var.retention_period_in_days
    error_message = "The retention_period_in_days must be a whole number from 1 to 1095."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of a customer managed KMS key that encrypts the workspace. Null uses an AWS owned key. Changing it replaces the workspace and its data."
  default     = null

  validation {
    condition     = try(trimspace(var.kms_key_arn), "") == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", trimspace(var.kms_key_arn)))
    error_message = "The kms_key_arn must be a KMS key ARN."
  }
}
