################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the SSM parameter or Secrets Manager secret. A leading slash is added for Parameter Store and removed for Secrets Manager."

  validation {
    condition     = can(regex("^/?[A-Za-z0-9_.+=@-]+(/[A-Za-z0-9_.+=@-]+)*$", var.name)) && length(var.name) <= 512
    error_message = "The name must be at most 512 characters of letters, numbers, and . _ - + = @ /, with no empty path segments."
  }

  validation {
    condition     = var.store != "parameter_store" || (can(regex("^/?[A-Za-z0-9_./-]+$", var.name)) && !can(regex("^/?(?i)(aws|ssm)", var.name)))
    error_message = "Parameter Store names may only contain letters, numbers, and . _ - /, and must not start with aws or ssm."
  }
}

variable "store" {
  type        = string
  description = "Where the generated value is stored: parameter_store (SSM SecureString) or secrets_manager."
  default     = "parameter_store"

  validation {
    condition     = contains(["parameter_store", "secrets_manager"], var.store)
    error_message = "The store must be parameter_store or secrets_manager."
  }
}

variable "description" {
  type        = string
  description = "Description for the parameter or secret. Defaults to a generated description."
  default     = null
}

################################################################################
# Generated value
################################################################################

variable "length" {
  type        = number
  description = "Number of characters in the generated value. Changes take effect on the next rotation."
  default     = 32

  validation {
    condition     = var.length >= 16 && var.length <= 512 && floor(var.length) == var.length
    error_message = "The length must be a whole number between 16 and 512."
  }
}

variable "special_characters" {
  type        = bool
  description = "Include special characters in the generated value. Disabled by default so the value is safe in URLs, headers, and connection strings. Changes take effect on the next rotation."
  default     = false
}

variable "rotation_version" {
  type        = number
  description = "Version of the generated value. Change it to generate and store a new value using the current length and special_characters."
  default     = 1

  validation {
    condition     = var.rotation_version >= 1 && floor(var.rotation_version) == var.rotation_version
    error_message = "The rotation_version must be a whole number of at least 1."
  }
}

################################################################################
# Encryption and deletion
################################################################################

variable "kms_key_id" {
  type        = string
  description = "KMS key ID, ARN, or alias used to encrypt the value. Defaults to the AWS managed key for the store (aws/ssm or aws/secretsmanager)."
  default     = null
}

variable "recovery_window_in_days" {
  type        = number
  description = "Days Secrets Manager keeps a deleted secret before removing it (0 to delete immediately, or 7-30). Ignored for Parameter Store."
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "The recovery_window_in_days must be 0 or between 7 and 30."
  }
}

################################################################################
# Tags and region
################################################################################

variable "tags" {
  type        = map(string)
  description = "A map of additional tags applied to the parameter or secret."
  default     = {}
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
