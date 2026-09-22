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
  default_tags = {
    ManagedBy = "terraform"
    Module    = "cdn/cloudfront"
  }

  tags = merge(local.default_tags, var.tags)
}
