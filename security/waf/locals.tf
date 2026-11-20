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

locals {
  priorities = merge({
    ip_allow      = 1
    ip_block      = 2
    geo_block     = 3
    custom_rules  = 5
    ip_reputation = 10
    rate_limit    = 20
    anonymous_ip  = 30
    bot_control   = 40
  }, var.rule_priorities)

  # IP sets hold one address family each.
  ip_sets = { for key, set in {
    "allow-ipv4" = { version = "IPV4", addresses = [for cidr in var.ip_allow_list : cidr if !strcontains(cidr, ":")] }
    "allow-ipv6" = { version = "IPV6", addresses = [for cidr in var.ip_allow_list : cidr if strcontains(cidr, ":")] }
    "block-ipv4" = { version = "IPV4", addresses = [for cidr in var.ip_block_list : cidr if !strcontains(cidr, ":")] }
    "block-ipv6" = { version = "IPV6", addresses = [for cidr in var.ip_block_list : cidr if strcontains(cidr, ":")] }
  } : key => set if length(set.addresses) > 0 }

  ip_allow_set_arns = [for key in ["allow-ipv4", "allow-ipv6"] : aws_wafv2_ip_set.this[key].arn if contains(keys(local.ip_sets), key)]
  ip_block_set_arns = [for key in ["block-ipv4", "block-ipv6"] : aws_wafv2_ip_set.this[key].arn if contains(keys(local.ip_sets), key)]

  anonymous_ip_overrides = merge(
    var.anonymous_ip_block_hosting_providers ? {} : { HostingProviderIPList = "count" },
    lookup(var.rule_action_overrides, "anonymous_ip", {}),
  )

  managed_rule_groups = [for group in var.managed_rule_groups : merge(group, {
    count_only = coalesce(group.count_only, var.count_only)
    paths_regex = length(group.paths) == 0 ? null : format(
      "^(%s)",
      join("|", [for path in group.paths : replace(lower(path), ".", "\\.")]),
    )
  })]

  rate_limit_response_body_key = "rate-limited"

  # Every rule in the web ACL needs its own priority.
  used_priorities = concat(
    length(var.ip_allow_list) > 0 ? [local.priorities.ip_allow] : [],
    length(var.ip_block_list) > 0 ? [local.priorities.ip_block] : [],
    length(var.blocked_country_codes) > 0 ? [local.priorities.geo_block] : [],
    var.custom_rules_json != null ? [local.priorities.custom_rules] : [],
    var.ip_reputation_enabled ? [local.priorities.ip_reputation] : [],
    local.protected_paths_regex != null ? [local.priorities.rate_limit] : [],
    var.anonymous_ip_enabled && local.protected_paths_regex != null ? [local.priorities.anonymous_ip] : [],
    local.bot_control_paths_regex != null ? [local.priorities.bot_control] : [],
    [for group in var.managed_rule_groups : group.priority],
  )
}
