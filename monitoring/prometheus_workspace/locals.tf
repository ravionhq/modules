################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "monitoring/prometheus_workspace"
  }

  tags = merge(local.default_tags, var.tags, { Name = var.name })

  # A form leaves an unused field blank rather than null.
  kms_key_arn = try(trimspace(var.kms_key_arn), "") == "" ? null : trimspace(var.kms_key_arn)

  # The workspace endpoint ends with a slash; the query API hangs off it.
  query_url        = trimsuffix(aws_prometheus_workspace.this.prometheus_endpoint, "/")
  remote_write_url = "${local.query_url}/api/v1/remote_write"
}
