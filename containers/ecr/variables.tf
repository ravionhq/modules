################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the ECR repository. Must be lowercase, 2-256 characters, and may contain letters, numbers, hyphens, underscores, periods, and forward slashes."

  validation {
    condition     = can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.name))
    error_message = "The name must start with a letter or number, contain only lowercase letters, numbers, hyphens, underscores, periods, and forward slashes, and not end with a separator."
  }

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 256
    error_message = "The name must be between 2 and 256 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Repository
################################################################################

variable "image_tag_mutability" {
  type        = string
  description = "The tag mutability setting for the repository. Set to IMMUTABLE to prevent tags from being overwritten."
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "The image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "image_scan_on_push_enabled" {
  type        = bool
  description = "Indicates whether images are scanned for vulnerabilities after being pushed."
  default     = true
}

variable "force_delete_enabled" {
  type        = bool
  description = "If true, the repository will be deleted even if it contains images. Use with caution."
  default     = false
}

################################################################################
# Encryption
################################################################################

variable "encryption_type" {
  type        = string
  description = "The encryption type for the repository. AES256 uses AWS-managed keys; KMS uses a customer-managed KMS key."
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "The encryption_type must be 'AES256' or 'KMS'."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key to use when encryption_type is KMS. If null with KMS, an AWS-managed KMS key is used."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be a valid KMS key ARN."
  }
}

################################################################################
# Lifecycle Policy
################################################################################

variable "lifecycle_policy" {
  type        = string
  description = "A raw JSON lifecycle policy document. If set, takes precedence over the built-in lifecycle rules below."
  default     = null
}

variable "default_lifecycle_policy_enabled" {
  type        = bool
  description = "Apply a built-in lifecycle policy that expires untagged images and caps the number of images retained, tagged or untagged. Ignored if lifecycle_policy is set."
  default     = false
}

variable "untagged_image_expiry_days" {
  type        = number
  description = "Number of days after which untagged images are expired. Used only when default_lifecycle_policy_enabled is true."
  default     = 14

  validation {
    condition     = var.untagged_image_expiry_days >= 1
    error_message = "The untagged_image_expiry_days must be at least 1."
  }
}

variable "max_tagged_image_count" {
  type        = number
  description = "Maximum number of images to retain, tagged or untagged. Older images beyond this count are expired. Used only when default_lifecycle_policy_enabled is true."
  default     = 100

  validation {
    condition     = var.max_tagged_image_count >= 1
    error_message = "The max_tagged_image_count must be at least 1."
  }
}

################################################################################
# Repository Policy
################################################################################

variable "repository_policy" {
  type        = string
  description = "A raw JSON repository policy document. If set, takes precedence over allowed_pull_principal_arns and allowed_push_principal_arns."
  default     = null
}

variable "allowed_pull_principal_arns" {
  type        = list(string)
  description = "A list of IAM principal ARNs granted pull access (read) to the repository. Used to generate a repository policy when repository_policy is null."
  default     = []
}

variable "allowed_push_principal_arns" {
  type        = list(string)
  description = "A list of IAM principal ARNs granted push access (read and write) to the repository. Used to generate a repository policy when repository_policy is null."
  default     = []
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
