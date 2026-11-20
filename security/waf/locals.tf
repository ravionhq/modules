locals {
  # CloudFront web ACLs are global and AWS only accepts them in us-east-1.
  scope  = var.target == "cloudfront" ? "CLOUDFRONT" : "REGIONAL"
  region = var.target == "cloudfront" ? "us-east-1" : coalesce(var.region, data.aws_region.current.region)

  # Each path is a lowercase prefix. Dots are escaped so a path matches
  # literally; the variable validation only allows URL path characters, so no
  # other regex metacharacter can reach a pattern.
  protected_paths_regex = length(var.protected_paths) == 0 ? null : format(
    "^(%s)",
    join("|", [for path in var.protected_paths : replace(lower(path), ".", "\\.")]),
  )
  bot_control_paths_regex = length(var.bot_control_paths) == 0 ? null : format(
    "^(%s)",
    join("|", [for path in var.bot_control_paths : replace(lower(path), ".", "\\.")]),
  )

  # CloudWatch metric names allow letters, digits, hyphens and underscores.
  metric_prefix = replace(var.name, "/[^A-Za-z0-9_-]/", "-")

  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/waf"
  }

  tags = merge(local.default_tags, var.tags)
}
