################################################################################
# CloudFront Distributions
#
# Composes cdn/cloudfront. All distributions share the same S3 hosting origin
# and cache behaviors; per-distribution config (aliases, ACM cert, comment)
# (or managed_domains, whose certificate Ravion attaches) comes from
# var.distributions and is forwarded as-is.
#
# The viewer-request CloudFront Function rewrites every URI to /<version>/...
# before the cache lookup, so each promoted version produces a fresh cache key
# automatically — no CreateInvalidation, no custom_error_responses needed.
#
# The viewer-response CloudFront Function (created when cache_control_enabled =
# true, the default) sets Cache-Control on every response based on the
# rewritten URI shape. These headers only steer the BROWSER — CloudFront
# ignores viewer-response headers for edge TTLs. HTML responses get
# revalidate-always, hashed assets get the immutable 1-year browser cache.
# See functions/cache_control.js for the classification rules.
################################################################################

module "cdn" {
  source = "../../cdn/cloudfront"

  providers = {
    aws = aws.us_east_1
  }

  name = var.name

  distributions = var.distributions

  anycast_ip_list_mode = var.anycast_ip_list_mode
  anycast_ip_list_id   = var.anycast_ip_list_id
  anycast_ip_count     = var.anycast_ip_count

  module_instance_id    = var.module_instance_id
  ravion_aws_account_id = var.ravion_aws_account_id

  origins = [
    {
      origin_id         = local.origin_id
      domain_name       = module.hosting.bucket_regional_domain_name
      s3_origin_enabled = true
      custom_headers    = var.additional_origin_headers
      origin_shield = var.origin_shield_enabled ? {
        enabled              = true
        origin_shield_region = local.origin_shield_region
      } : null
    }
  ]

  default_cache_behavior = {
    target_origin_id             = local.origin_id
    viewer_protocol_policy       = "redirect-to-https"
    allowed_methods              = ["GET", "HEAD", "OPTIONS"]
    cached_methods               = ["GET", "HEAD"]
    compression_enabled          = true
    cache_policy_id              = local.effective_cache_policy_id
    origin_request_policy_id     = var.origin_request_policy_id
    response_headers_policy_id   = local.effective_response_headers_policy_id
    function_associations        = local.cff_associations
    lambda_function_associations = []
  }

  ordered_cache_behaviors = local.ordered_behaviors

  custom_error_responses = local.custom_error_responses

  default_root_object     = var.default_root_object
  price_class             = var.price_class
  http_version            = "http2and3"
  ipv6_enabled            = true
  deployment_wait_enabled = var.deployment_wait_enabled

  minimum_protocol_version = var.minimum_protocol_version

  geo_restriction_type      = var.geo_restriction_type
  geo_restriction_locations = var.geo_restriction_locations

  web_acl_id = var.web_acl_id

  logging_enabled                 = var.logging_enabled
  logging_destination             = var.logging_destination
  logging_bucket_creation_enabled = var.logging_bucket_creation_enabled
  logging_bucket_domain_name      = var.logging_bucket_domain_name
  logging_prefix                  = var.logging_prefix
  logging_bucket_retention_days   = var.logging_retention_days

  tags = local.tags
}
