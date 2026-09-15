################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_subnet" "selected" {
  for_each = toset(var.subnet_ids)

  id = each.value
}

data "tls_certificate" "oidc" {
  count = var.oidc_provider_creation_enabled ? 1 : 0

  url = local.oidc_issuer
}
