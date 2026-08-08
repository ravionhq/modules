resource "aws_cloudfront_distribution" "this" {
  for_each = var.distributions

  enabled             = each.value.enabled
  comment             = each.value.comment != null ? each.value.comment : "${var.name}-${each.key}"
  price_class         = var.price_class
  http_version        = var.http_version
  is_ipv6_enabled     = var.ipv6_enabled
  default_root_object = var.default_root_object
  retain_on_delete    = var.retain_on_delete_enabled
  wait_for_deployment = var.deployment_wait_enabled
  aliases             = each.value.aliases
  web_acl_id          = var.web_acl_id

  dynamic "origin" {
    for_each = var.origins
    content {
      origin_id   = origin.value.origin_id
      domain_name = origin.value.domain_name
      origin_path = origin.value.origin_path

      origin_access_control_id = origin.value.s3_origin_enabled && var.origin_access_control_creation_enabled ? (
        origin.value.origin_access_control_id != null ? origin.value.origin_access_control_id : aws_cloudfront_origin_access_control.this[origin.value.origin_id].id
      ) : origin.value.origin_access_control_id

      dynamic "custom_origin_config" {
        for_each = origin.value.s3_origin_enabled || origin.value.vpc_origin_enabled ? [] : [1]
        content {
          http_port                = origin.value.http_port
          https_port               = origin.value.https_port
          origin_protocol_policy   = origin.value.origin_protocol_policy
          origin_ssl_protocols     = origin.value.origin_ssl_protocols
          origin_keepalive_timeout = origin.value.origin_keepalive_timeout
          origin_read_timeout      = origin.value.origin_read_timeout
        }
      }

      dynamic "vpc_origin_config" {
        for_each = origin.value.vpc_origin_enabled ? [1] : []
        content {
          vpc_origin_id            = aws_cloudfront_vpc_origin.this[origin.value.origin_id].id
          origin_keepalive_timeout = origin.value.origin_keepalive_timeout
          origin_read_timeout      = origin.value.origin_read_timeout
        }
      }

      dynamic "custom_header" {
        for_each = origin.value.custom_headers
        content {
          name  = custom_header.value.name
          value = custom_header.value.value
        }
      }

      dynamic "origin_shield" {
        for_each = origin.value.origin_shield != null ? [origin.value.origin_shield] : []
        content {
          enabled              = origin_shield.value.enabled
          origin_shield_region = origin_shield.value.origin_shield_region
        }
      }

      connection_attempts = origin.value.connection_attempts
      connection_timeout  = origin.value.connection_timeout
    }
  }

  default_cache_behavior {
    target_origin_id           = var.default_cache_behavior.target_origin_id
    viewer_protocol_policy     = var.default_cache_behavior.viewer_protocol_policy
    allowed_methods            = var.default_cache_behavior.allowed_methods
    cached_methods             = var.default_cache_behavior.cached_methods
    compress                   = var.default_cache_behavior.compression_enabled
    cache_policy_id            = local.effective_default_cache_policy_id
    origin_request_policy_id   = var.default_cache_behavior.origin_request_policy_id
    response_headers_policy_id = var.default_cache_behavior.response_headers_policy_id
    trusted_key_groups         = var.default_cache_behavior.trusted_key_groups

    dynamic "function_association" {
      for_each = concat(var.default_cache_behavior.function_associations, local.redirect_function_associations)
      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }

    dynamic "lambda_function_association" {
      for_each = var.default_cache_behavior.lambda_function_associations
      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = lambda_function_association.value.lambda_arn
        include_body = lambda_function_association.value.body_inclusion_enabled
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors
    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy     = ordered_cache_behavior.value.viewer_protocol_policy
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cached_methods             = ordered_cache_behavior.value.cached_methods
      compress                   = ordered_cache_behavior.value.compression_enabled
      cache_policy_id            = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id   = ordered_cache_behavior.value.origin_request_policy_id
      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id
      trusted_key_groups         = ordered_cache_behavior.value.trusted_key_groups

      dynamic "function_association" {
        for_each = concat(ordered_cache_behavior.value.function_associations, local.redirect_function_associations)
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = ordered_cache_behavior.value.lambda_function_associations
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.lambda_arn
          include_body = lambda_function_association.value.body_inclusion_enabled
        }
      }
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = each.value.acm_certificate_arn == null ? true : false
    acm_certificate_arn            = each.value.acm_certificate_arn
    minimum_protocol_version       = each.value.acm_certificate_arn != null ? var.minimum_protocol_version : null
    ssl_support_method             = each.value.acm_certificate_arn != null ? var.ssl_support_method : null
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  dynamic "logging_config" {
    for_each = local.s3_logging_enabled ? [1] : []
    content {
      bucket          = var.logging_bucket_creation_enabled ? aws_s3_bucket.logging[0].bucket_domain_name : var.logging_bucket_domain_name
      prefix          = "${var.logging_prefix}${each.key}/"
      include_cookies = var.logging_cookies_enabled
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })

  lifecycle {
    precondition {
      condition = !local.redirects_enabled || !(
        local.default_viewer_request_function_conflict ||
        local.default_viewer_request_lambda_conflict ||
        local.ordered_viewer_request_function_conflict ||
        local.ordered_viewer_request_lambda_conflict
      )
      error_message = "redirect_rules cannot be enabled when a default or ordered cache behavior already has a viewer-request CloudFront Function or Lambda@Edge association."
    }
  }
}
