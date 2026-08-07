locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/rds-proxy"
  }
  tags = merge(local.default_tags, var.tags)

  # Port defaults based on engine family
  default_port = (
    var.engine_family == "POSTGRESQL" ? 5432 :
    var.engine_family == "SQLSERVER" ? 1433 :
    3306
  )
  port = coalesce(var.port, local.default_port)

  # Resource creation flags
  create_security_group = var.security_group_creation_enabled
  create_iam_role       = var.iam_role_creation_enabled

  # Resolved resource references
  security_group_id = local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id
  iam_role_arn      = local.create_iam_role ? aws_iam_role.this[0].arn : var.iam_role_arn

  # Secrets the proxy IAM role must be able to read
  auth_secret_arns = distinct([for a in var.auth : a.secret_arn])
}
