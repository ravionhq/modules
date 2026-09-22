################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Short, human-readable name for the key. Used as the alias suffix (alias/<name>) when var.alias is null and as a stable handle in tags / descriptions."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64
    error_message = "The name must be between 1 and 64 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.name))
    error_message = "The name must contain only alphanumerics, hyphens, underscores, and forward slashes (KMS alias-name constraints)."
  }
}

variable "description" {
  type        = string
  description = "Free-form description for the KMS key. Defaults to a generated string referencing var.name."
  default     = null
}

variable "alias" {
  type        = string
  description = "Optional alias name (without the 'alias/' prefix). Defaults to var.name. The module always prepends 'alias/'."
  default     = null

  validation {
    condition     = var.alias == null || can(regex("^[a-zA-Z0-9/_-]+$", var.alias))
    error_message = "The alias must contain only alphanumerics, hyphens, underscores, and forward slashes."
  }
}

################################################################################
# Cryptographic shape
################################################################################

variable "key_spec" {
  type        = string
  description = "Cryptographic configuration of the key. Pairs with key_usage (e.g. RSA_2048+SIGN_VERIFY for OIDC JWT signing, SYMMETRIC_DEFAULT+ENCRYPT_DECRYPT for envelope encryption, HMAC_256+GENERATE_VERIFY_MAC for MAC, ECC_NIST_P256+SIGN_VERIFY for ECDSA)."
  default     = "SYMMETRIC_DEFAULT"

  validation {
    condition = contains(
      [
        "SYMMETRIC_DEFAULT",
        "RSA_2048", "RSA_3072", "RSA_4096",
        "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521",
        "ECC_SECG_P256K1",
        "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512",
        "SM2",
      ],
      var.key_spec,
    )
    error_message = "The key_spec must be one of the AWS KMS-supported specs (SYMMETRIC_DEFAULT, RSA_*, ECC_*, HMAC_*, SM2)."
  }
}

variable "key_usage" {
  type        = string
  description = "Intended use of the key. Must be valid for the chosen key_spec: SYMMETRIC_DEFAULT supports ENCRYPT_DECRYPT or GENERATE_VERIFY_MAC (HMAC); RSA supports ENCRYPT_DECRYPT or SIGN_VERIFY; ECC supports SIGN_VERIFY (or KEY_AGREEMENT for ECC_NIST_P256/P384/P521); HMAC_* requires GENERATE_VERIFY_MAC; SM2 supports ENCRYPT_DECRYPT, SIGN_VERIFY, or KEY_AGREEMENT."
  default     = "ENCRYPT_DECRYPT"

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC", "KEY_AGREEMENT"], var.key_usage)
    error_message = "The key_usage must be one of: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, KEY_AGREEMENT."
  }
}

variable "multi_region_enabled" {
  type        = bool
  description = "Whether to create the key as a multi-region primary key (replicas can later be created via aws_kms_replica_key)."
  default     = false
}

variable "key_rotation_enabled" {
  type        = bool
  description = "Enable annual automatic rotation of the key material. AWS only supports automatic rotation for symmetric keys (SYMMETRIC_DEFAULT + ENCRYPT_DECRYPT); the module ignores this setting for any other shape."
  default     = true
}

variable "deletion_window_in_days" {
  type        = number
  description = "Waiting period before a scheduled key deletion becomes permanent. AWS KMS allows 7-30 days. Defaults to 30 (the maximum safety window) so an accidental delete is maximally recoverable."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "The deletion_window_in_days must be between 7 and 30 (AWS KMS requirement)."
  }
}

################################################################################
# Key policy principals
#
# Each list maps to an optional statement in the key policy. Empty lists omit
# the statement entirely, which is useful for a bootstrap apply where the
# consuming role does not yet exist.
#
# IMPORTANT: principals are typed loosely as list(string) so callers can pass
# IAM role ARNs, IAM user ARNs, or account roots
# ('arn:aws:iam::<account>:root').
################################################################################

variable "key_administrator_role_arns" {
  type        = list(string)
  description = "IAM principals granted administrative actions on the key (describe, alias management, deletion scheduling, policy updates). Does NOT grant cryptographic operations. Leave empty to rely on the account root's IAM-granted permissions (the standard AWS KMS pattern)."
  default     = []

  validation {
    condition     = alltrue([for arn in var.key_administrator_role_arns : can(regex("^arn:aws(-us-gov|-cn|-iso|-iso-b|-iso-e|-iso-f)?:iam::[0-9]{12}:(root|(role|user)/[!-~]*[A-Za-z0-9+=,.@_-])$", arn))])
    error_message = "Every entry in key_administrator_role_arns must be an account root, role, or user ARN with a 12-digit account ID."
  }
}

variable "key_user_role_arns" {
  type        = list(string)
  description = "IAM principals permitted to use the key for cryptographic operations matching its key_usage. For ENCRYPT_DECRYPT: kms:Encrypt, Decrypt, ReEncrypt*, GenerateDataKey*, DescribeKey. For SIGN_VERIFY: kms:Verify, GetPublicKey, DescribeKey (use signer_role_arns for Sign). For GENERATE_VERIFY_MAC: kms:GenerateMac, VerifyMac, DescribeKey. Empty by default so the key can be provisioned before its consumers exist."
  default     = []

  validation {
    condition     = alltrue([for arn in var.key_user_role_arns : can(regex("^arn:aws(-us-gov|-cn|-iso|-iso-b|-iso-e|-iso-f)?:iam::[0-9]{12}:(root|(role|user)/[!-~]*[A-Za-z0-9+=,.@_-])$", arn))])
    error_message = "Every entry in key_user_role_arns must be an account root, role, or user ARN with a 12-digit account ID."
  }
}

variable "signer_role_arns" {
  type        = list(string)
  description = "IAM principals permitted to call kms:Sign / kms:GenerateMac (depending on key_usage). Only applies when key_usage is SIGN_VERIFY or GENERATE_VERIFY_MAC. Granted alongside kms:DescribeKey and kms:GetPublicKey so signers can self-introspect. Empty by default so the key can be provisioned before its consumers exist."
  default     = []

  validation {
    condition     = alltrue([for arn in var.signer_role_arns : can(regex("^arn:aws(-us-gov|-cn|-iso|-iso-b|-iso-e|-iso-f)?:iam::[0-9]{12}:(root|(role|user)/[!-~]*[A-Za-z0-9+=,.@_-])$", arn))])
    error_message = "Every entry in signer_role_arns must be an account root, role, or user ARN with a 12-digit account ID."
  }
}

variable "public_key_reader_role_arns" {
  type        = list(string)
  description = "IAM principals permitted to call kms:GetPublicKey and kms:DescribeKey. Explicitly does NOT grant kms:Sign or kms:Verify, so a compromised reader cannot forge or validate signatures. Useful for JWKS publishers and similar 'export the public half' workflows."
  default     = []

  validation {
    condition     = alltrue([for arn in var.public_key_reader_role_arns : can(regex("^arn:aws(-us-gov|-cn|-iso|-iso-b|-iso-e|-iso-f)?:iam::[0-9]{12}:(root|(role|user)/[!-~]*[A-Za-z0-9+=,.@_-])$", arn))])
    error_message = "Every entry in public_key_reader_role_arns must be an account root, role, or user ARN with a 12-digit account ID."
  }
}

################################################################################
# Tags
################################################################################

variable "tags" {
  type        = map(string)
  description = "A map of additional tags applied to both the KMS key and the alias."
  default     = {}
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
