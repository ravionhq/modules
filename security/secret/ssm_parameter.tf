################################################################################
# SSM Parameter Store
################################################################################

resource "aws_ssm_parameter" "this" {
  count = local.use_parameter_store ? 1 : 0

  name        = local.parameter_name
  description = local.description
  type        = "SecureString"
  tier        = "Standard"
  key_id      = var.kms_key_id

  value_wo         = ephemeral.random_password.this.result
  value_wo_version = var.rotation_version

  tags = local.tags
}
