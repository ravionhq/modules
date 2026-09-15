################################################################################
# Secrets Envelope Encryption Key
#
# Created only when var.secrets_encryption_enabled is true and the caller did
# not pass an existing key via var.secrets_kms_key_arn. The cluster role is
# granted use of the key via aws_kms_grant below; the security/kms module
# itself only manages the key shape and tags.
################################################################################

module "secrets_kms" {
  count = var.secrets_encryption_enabled && var.secrets_kms_key_arn == null ? 1 : 0

  source = "../../../../security/kms"

  name        = "${var.name}-secrets"
  description = "EKS Kubernetes secrets envelope encryption for ${var.name}"

  key_user_role_arns = [module.cluster_role.role_arn]

  tags = local.tags
}
