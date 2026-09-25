################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  use_parameter_store = var.store == "parameter_store"
  use_secrets_manager = var.store == "secrets_manager"

  parameter_name = "/${trimprefix(var.name, "/")}"
  secret_name    = trimprefix(var.name, "/")

  description = coalesce(var.description, "Generated secret ${local.secret_name}. Managed by Ravion; the value is never stored in Terraform state.")

  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/generated_secret"
  }

  tags = merge(local.default_tags, var.tags)
}
