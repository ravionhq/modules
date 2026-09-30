locals {
  region = coalesce(var.region, data.aws_region.current.region)

  redirects_enabled               = length(var.redirect_rules) > 0
  viewer_request_function_enabled = local.redirects_enabled
  viewer_request_function_name = format(
    "%s-%s",
    substr(replace("${var.name}-redirect", "/[^a-zA-Z0-9-_]/", "-"), 0, 55),
    substr(md5(var.name), 0, 8),
  )
  viewer_request_function_code = templatefile("${path.module}/functions/viewer_request.js", {
    redirect_rules_json = jsonencode(var.redirect_rules)
  })
  viewer_request_function_associations = local.viewer_request_function_enabled ? [{
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.viewer_request[0].arn
  }] : []

  default_viewer_request_function_conflict = anytrue([
    for association in var.default_cache_behavior.function_associations :
    association.event_type == "viewer-request"
  ])
  default_viewer_request_lambda_conflict = anytrue([
    for association in var.default_cache_behavior.lambda_function_associations :
    association.event_type == "viewer-request"
  ])
  ordered_viewer_request_function_conflict = anytrue(flatten([
    for behavior in var.ordered_cache_behaviors : [
      for association in behavior.function_associations :
      association.event_type == "viewer-request"
    ]
  ]))
  ordered_viewer_request_lambda_conflict = anytrue(flatten([
    for behavior in var.ordered_cache_behaviors : [
      for association in behavior.lambda_function_associations :
      association.event_type == "viewer-request"
    ]
  ]))
}

locals {
  vpc_origin_endpoints = {
    for o in var.origins : o.origin_id => {
      arn                    = o.vpc_origin_arn
      http_port              = o.http_port
      https_port             = o.https_port
      origin_protocol_policy = o.origin_protocol_policy
      origin_ssl_protocols   = o.origin_ssl_protocols
      base_name              = "${var.name}-${o.origin_id}"
    } if o.vpc_origin_enabled
  }

  # The hash suffix gives each endpoint configuration its own name, so the
  # replacement VPC origin can exist alongside the one it replaces.
  vpc_origin_names = {
    for k, v in local.vpc_origin_endpoints : k => format(
      "%s-%s",
      substr(replace(v.base_name, "/[^a-zA-Z0-9-_]/", "-"), 0, 55),
      substr(sha1(jsonencode(v)), 0, 8),
    )
  }
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "cdn/cloudfront"
  }

  tags = merge(local.default_tags, var.tags)
}
