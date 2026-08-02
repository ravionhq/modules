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
    Module    = "networking/alb"
  }
  tags = merge(local.default_tags, var.tags)

  # Access Logs
  create_access_logs_bucket = var.access_logs_enabled && var.access_logs_bucket_arn == null
  access_logs_bucket_name = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : (
    var.access_logs_bucket_arn != null ? regex("arn:aws:s3:::(.+)", var.access_logs_bucket_arn)[0] : null
  )

  # Listener configuration
  create_http_listener  = var.http_listener_enabled
  create_https_listener = var.https_listener_enabled

  # IPv6 ingress defaults depend on visibility: internet-facing allows all IPv6
  # sources, internal allows none (RFC1918 has no IPv6 equivalent).
  ingress_ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks != null ? var.ingress_ipv6_cidr_blocks : (var.internal_load_balancer_enabled ? [] : ["::/0"])
}
