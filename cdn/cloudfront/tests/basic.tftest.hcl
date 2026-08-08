################################################################################
# CloudFront Module Unit Tests
################################################################################

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_resource {
    target = aws_cloudfront_distribution.this
    values = {
      arn                            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
      domain_name                    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id                 = "Z2FDTNDATAQYW2"
      status                         = "Deployed"
      etag                           = "E2QWRUHEXAMPLE"
      id                             = "EDFDVBD6EXAMPLE"
      caller_reference               = "test-ref-001"
      in_progress_validation_batches = 0
    }
  }

  override_resource {
    target = aws_cloudfront_cache_policy.accept_header
    values = {
      id = "accept-header-cache-policy-test"
    }
  }

  override_resource {
    target = aws_cloudfront_function.redirect
    values = {
      arn    = "arn:aws:cloudfront::123456789012:function/test-cf-redirect"
      status = "DEPLOYED"
    }
  }

  override_resource {
    target = aws_s3_bucket.logging
    values = {
      arn                = "arn:aws:s3:::test-cf-logs-123456789012-us-east-1"
      id                 = "test-cf-logs-123456789012-us-east-1"
      bucket_domain_name = "test-cf-logs-123456789012-us-east-1.s3.amazonaws.com"
    }
  }

  # The delivery-source and delivery-destination resources validate their ARN
  # attributes at plan time, so mocked upstream ARNs must be well-formed.
  override_resource {
    target = aws_cloudwatch_log_group.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/test-cf"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_delivery_destination.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:test-cf-access-logs-cw"
    }
  }
}

# Default variables for all tests
variables {
  name = "test-cf"
  distributions = {
    primary = {}
  }
  origins = [
    {
      origin_id         = "s3-origin"
      domain_name       = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin_enabled = true
    }
  ]
  default_cache_behavior = {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
  }
}

#-------------------------------------------------------------------------------
# Name Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid name - basic
run "test_name_validation_valid_basic" {
  command = plan

  assert {
    condition     = var.name == "test-cf"
    error_message = "Valid name should be accepted."
  }
}

# Test: Valid name - with numbers
run "test_name_validation_valid_with_numbers" {
  command = plan

  variables {
    name = "cf123test"
  }

  assert {
    condition     = var.name == "cf123test"
    error_message = "Valid name with numbers should be accepted."
  }
}

# Test: Invalid name - empty
run "test_name_validation_empty" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - too long (more than 63 characters)
run "test_name_validation_max_length" {
  command = plan

  variables {
    name = "this-cloudfront-name-is-way-too-long-and-exceeds-the-sixty-three-character-limit"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - starts with number
run "test_name_validation_starts_with_number" {
  command = plan

  variables {
    name = "123-invalid"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - contains underscores
run "test_name_validation_invalid_underscore" {
  command = plan

  variables {
    name = "my_test_cf"
  }

  expect_failures = [
    var.name,
  ]
}

#-------------------------------------------------------------------------------
# Distributions Validation Tests
#-------------------------------------------------------------------------------

# Test: Invalid distributions - empty map
run "test_distributions_empty" {
  command = plan

  variables {
    distributions = {}
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Valid distributions - single with defaults
run "test_distributions_single_defaults" {
  command = plan

  variables {
    distributions = {
      primary = {}
    }
  }

  assert {
    condition     = var.distributions["primary"].enabled == true
    error_message = "Distribution enabled should default to true."
  }

  assert {
    condition     = length(var.distributions["primary"].aliases) == 0
    error_message = "Distribution aliases should default to empty list."
  }
}

# Test: Valid distributions - multiple distributions
run "test_distributions_multiple" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com", "www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      staging = {
        aliases             = ["staging.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/87654321-4321-4321-4321-210987654321"
        comment             = "Staging distribution"
      }
    }
  }

  assert {
    condition     = length(var.distributions) == 2
    error_message = "Two distributions should be accepted."
  }
}

# Test: Invalid distributions - aliases without cert
run "test_distributions_aliases_without_cert" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases = ["example.com"]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Invalid distributions - invalid ACM ARN
run "test_distributions_invalid_acm_arn" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com"]
        acm_certificate_arn = "arn:aws:iam::123456789012:role/my-role"
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

# Test: Invalid distributions - duplicate aliases across distributions
run "test_distributions_duplicate_aliases" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["example.com", "www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      secondary = {
        aliases             = ["example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/87654321-4321-4321-4321-210987654321"
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

#-------------------------------------------------------------------------------
# Price Class Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid price_class - PriceClass_100
run "test_price_class_valid_100" {
  command = plan

  variables {
    price_class = "PriceClass_100"
  }

  assert {
    condition     = var.price_class == "PriceClass_100"
    error_message = "PriceClass_100 should be accepted."
  }
}

# Test: Valid price_class - PriceClass_200
run "test_price_class_valid_200" {
  command = plan

  variables {
    price_class = "PriceClass_200"
  }

  assert {
    condition     = var.price_class == "PriceClass_200"
    error_message = "PriceClass_200 should be accepted."
  }
}

# Test: Valid price_class - PriceClass_All
run "test_price_class_valid_all" {
  command = plan

  variables {
    price_class = "PriceClass_All"
  }

  assert {
    condition     = var.price_class == "PriceClass_All"
    error_message = "PriceClass_All should be accepted."
  }
}

# Test: Invalid price_class
run "test_price_class_invalid" {
  command = plan

  variables {
    price_class = "PriceClass_Invalid"
  }

  expect_failures = [
    var.price_class,
  ]
}

#-------------------------------------------------------------------------------
# HTTP Version Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid http_version - http2and3
run "test_http_version_valid_http2and3" {
  command = plan

  assert {
    condition     = var.http_version == "http2and3"
    error_message = "http2and3 should be the default."
  }
}

# Test: Valid http_version - http2
run "test_http_version_valid_http2" {
  command = plan

  variables {
    http_version = "http2"
  }

  assert {
    condition     = var.http_version == "http2"
    error_message = "http2 should be accepted."
  }
}

# Test: Invalid http_version
run "test_http_version_invalid" {
  command = plan

  variables {
    http_version = "http3"
  }

  expect_failures = [
    var.http_version,
  ]
}

#-------------------------------------------------------------------------------
# Geo Restriction Type Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid geo_restriction_type - none (default)
run "test_geo_restriction_type_valid_none" {
  command = plan

  assert {
    condition     = var.geo_restriction_type == "none"
    error_message = "none should be the default geo_restriction_type."
  }
}

# Test: Valid geo_restriction_type - whitelist
run "test_geo_restriction_type_valid_whitelist" {
  command = plan

  variables {
    geo_restriction_type      = "whitelist"
    geo_restriction_locations = ["US", "CA"]
  }

  assert {
    condition     = var.geo_restriction_type == "whitelist"
    error_message = "whitelist should be accepted."
  }
}

# Test: Valid geo_restriction_type - blacklist
run "test_geo_restriction_type_valid_blacklist" {
  command = plan

  variables {
    geo_restriction_type      = "blacklist"
    geo_restriction_locations = ["CN", "RU"]
  }

  assert {
    condition     = var.geo_restriction_type == "blacklist"
    error_message = "blacklist should be accepted."
  }
}

# Test: Invalid geo_restriction_type
run "test_geo_restriction_type_invalid" {
  command = plan

  variables {
    geo_restriction_type = "allow"
  }

  expect_failures = [
    var.geo_restriction_type,
  ]
}

#-------------------------------------------------------------------------------
# Viewer Protocol Policy Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid viewer_protocol_policy - redirect-to-https
run "test_viewer_protocol_policy_valid_redirect" {
  command = plan

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "redirect-to-https"
    error_message = "redirect-to-https should be accepted."
  }
}

# Test: Valid viewer_protocol_policy - https-only
run "test_viewer_protocol_policy_valid_https_only" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "https-only"
    }
  }

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "https-only"
    error_message = "https-only should be accepted."
  }
}

# Test: Valid viewer_protocol_policy - allow-all
run "test_viewer_protocol_policy_valid_allow_all" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "allow-all"
    }
  }

  assert {
    condition     = var.default_cache_behavior.viewer_protocol_policy == "allow-all"
    error_message = "allow-all should be accepted."
  }
}

# Test: Invalid viewer_protocol_policy
run "test_viewer_protocol_policy_invalid" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "http-only"
    }
  }

  expect_failures = [
    var.default_cache_behavior,
  ]
}

#-------------------------------------------------------------------------------
# SSL Support Method Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid ssl_support_method - sni-only (default)
run "test_ssl_support_method_valid_sni_only" {
  command = plan

  assert {
    condition     = var.ssl_support_method == "sni-only"
    error_message = "sni-only should be the default."
  }
}

# Test: Valid ssl_support_method - vip
run "test_ssl_support_method_valid_vip" {
  command = plan

  variables {
    ssl_support_method = "vip"
  }

  assert {
    condition     = var.ssl_support_method == "vip"
    error_message = "vip should be accepted."
  }
}

# Test: Invalid ssl_support_method
run "test_ssl_support_method_invalid" {
  command = plan

  variables {
    ssl_support_method = "dedicated-ip"
  }

  expect_failures = [
    var.ssl_support_method,
  ]
}

#-------------------------------------------------------------------------------
# WAF Web ACL ARN Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid web_acl_id - null (default)
run "test_web_acl_id_valid_null" {
  command = plan

  assert {
    condition     = var.web_acl_id == null
    error_message = "web_acl_id should default to null."
  }
}

# Test: Valid web_acl_id - valid ARN
run "test_web_acl_id_valid_arn" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = var.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/12345678-1234-1234-1234-123456789012"
    error_message = "Valid WAFv2 ARN should be accepted."
  }
}

# Test: Invalid web_acl_id - not a WAFv2 ARN
run "test_web_acl_id_invalid" {
  command = plan

  variables {
    web_acl_id = "arn:aws:waf::123456789012:webacl/my-acl"
  }

  expect_failures = [
    var.web_acl_id,
  ]
}

#-------------------------------------------------------------------------------
# Minimum Protocol Version Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid minimum_protocol_version - default
run "test_minimum_protocol_version_valid_default" {
  command = plan

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2021"
    error_message = "TLSv1.2_2021 should be the default."
  }
}

# Test: Valid minimum_protocol_version - TLSv1.2_2019
run "test_minimum_protocol_version_valid_2019" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.2_2019"
  }

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2019"
    error_message = "TLSv1.2_2019 should be accepted."
  }
}

# Test: Invalid minimum_protocol_version
run "test_minimum_protocol_version_invalid" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.3"
  }

  expect_failures = [
    var.minimum_protocol_version,
  ]
}

#-------------------------------------------------------------------------------
# Origin Validation Tests
#-------------------------------------------------------------------------------

# Test: Invalid origins - empty list
run "test_origins_validation_empty" {
  command = plan

  variables {
    origins = []
  }

  expect_failures = [
    var.origins,
  ]
}

# Test: Invalid origins - duplicate origin_id
run "test_origins_validation_duplicate_id" {
  command = plan

  variables {
    origins = [
      {
        origin_id         = "same-id"
        domain_name       = "bucket1.s3.amazonaws.com"
        s3_origin_enabled = true
      },
      {
        origin_id         = "same-id"
        domain_name       = "bucket2.s3.amazonaws.com"
        s3_origin_enabled = true
      }
    ]
  }

  expect_failures = [
    var.origins,
  ]
}

# Test: Valid origins - multiple origins
run "test_origins_validation_multiple" {
  command = plan

  variables {
    origins = [
      {
        origin_id         = "s3-origin"
        domain_name       = "my-bucket.s3.us-east-1.amazonaws.com"
        s3_origin_enabled = true
      },
      {
        origin_id   = "alb-origin"
        domain_name = "my-alb-123.us-east-1.elb.amazonaws.com"
      }
    ]
  }

  assert {
    condition     = length(var.origins) == 2
    error_message = "Two origins should be accepted."
  }
}

#-------------------------------------------------------------------------------
# VPC Origin Tests
#-------------------------------------------------------------------------------

# Test: VPC origin creates the VPC origin resource and uses vpc_origin_config
run "test_vpc_origin_created" {
  command = plan

  variables {
    origins = [
      {
        origin_id          = "alb-origin"
        domain_name        = "website.private.example.com"
        vpc_origin_enabled = true
        vpc_origin_arn     = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/1234567890abcdef"
      }
    ]
    default_cache_behavior = {
      target_origin_id       = "alb-origin"
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this) == 1
    error_message = "A VPC origin resource should be created when vpc_origin_enabled is true."
  }

  assert {
    condition     = aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].arn == "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/1234567890abcdef"
    error_message = "The VPC origin endpoint should target the provided load balancer ARN."
  }

  assert {
    condition     = aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].origin_protocol_policy == "https-only"
    error_message = "The VPC origin endpoint should use the origin's protocol policy."
  }

  assert {
    condition     = length([for o in aws_cloudfront_distribution.this["primary"].origin : o if length(o.vpc_origin_config) == 1]) == 1
    error_message = "The distribution origin should be configured with vpc_origin_config."
  }

  assert {
    condition     = length([for o in aws_cloudfront_distribution.this["primary"].origin : o if length(o.custom_origin_config) > 0]) == 0
    error_message = "No custom_origin_config should be emitted for a VPC-enabled origin."
  }
}

# Test: No VPC origin resources are created by default
run "test_vpc_origin_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this) == 0
    error_message = "No VPC origin resources should be created when vpc_origin_enabled is not set."
  }
}

# Test: Invalid origins - vpc_origin_enabled without vpc_origin_arn
run "test_vpc_origin_requires_arn" {
  command = plan

  variables {
    origins = [
      {
        origin_id          = "alb-origin"
        domain_name        = "website.private.example.com"
        vpc_origin_enabled = true
      }
    ]
    default_cache_behavior = {
      target_origin_id       = "alb-origin"
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  expect_failures = [
    var.origins,
  ]
}

# Test: Invalid origins - vpc_origin_enabled and s3_origin_enabled together
run "test_vpc_origin_conflicts_with_s3" {
  command = plan

  variables {
    origins = [
      {
        origin_id          = "mixed-origin"
        domain_name        = "my-bucket.s3.us-east-1.amazonaws.com"
        s3_origin_enabled  = true
        vpc_origin_enabled = true
        vpc_origin_arn     = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/1234567890abcdef"
      }
    ]
    default_cache_behavior = {
      target_origin_id       = "mixed-origin"
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  expect_failures = [
    var.origins,
  ]
}

#-------------------------------------------------------------------------------
# Logging Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid logging_bucket_retention_days
run "test_logging_retention_valid" {
  command = plan

  variables {
    logging_bucket_retention_days = 30
  }

  assert {
    condition     = var.logging_bucket_retention_days == 30
    error_message = "30 days retention should be accepted."
  }
}

# Test: Invalid logging_bucket_retention_days - zero
run "test_logging_retention_invalid_zero" {
  command = plan

  variables {
    logging_bucket_retention_days = 0
  }

  expect_failures = [
    var.logging_bucket_retention_days,
  ]
}

# Test: Invalid logging_bucket_retention_days - not a CloudWatch retention value
# while logging_destination is 'cloudwatch' (the default)
run "test_logging_retention_invalid_cloudwatch_value" {
  command = plan

  variables {
    logging_bucket_retention_days = 45
  }

  expect_failures = [
    var.logging_bucket_retention_days,
  ]
}

# Test: 45 days is a valid S3 lifecycle expiry when logging_destination is 's3'
run "test_logging_retention_non_cloudwatch_value_valid_for_s3" {
  command = plan

  variables {
    logging_destination             = "s3"
    logging_bucket_creation_enabled = true
    logging_bucket_retention_days   = 45
  }

  assert {
    condition     = var.logging_bucket_retention_days == 45
    error_message = "Any retention >= 1 should be accepted when logging_destination is 's3'."
  }
}

# Test: Invalid logging_destination
run "test_logging_destination_invalid" {
  command = plan

  variables {
    logging_destination = "firehose"
  }

  expect_failures = [
    var.logging_destination,
  ]
}

# Test: Default logging creates the CloudWatch delivery chain (logging is on
# by default with the 'cloudwatch' destination)
run "test_logging_default_creates_cloudwatch_chain" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 1
    error_message = "CloudWatch logging (the default) must create the access-log group."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.access_logs) == 1 && length(aws_cloudwatch_log_delivery.access_logs) == 1
    error_message = "One delivery source and one delivery must be created per distribution."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.access_logs) == 1
    error_message = "Exactly one shared delivery destination must be created."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].retention_in_days == 90
    error_message = "The log group retention must follow logging_bucket_retention_days."
  }

  assert {
    condition     = length(aws_s3_bucket.logging) == 0
    error_message = "No S3 logging bucket should be created when the destination is 'cloudwatch'."
  }
}

# Test: S3 destination keeps the bucket path and creates no CloudWatch resources
run "test_logging_s3_destination_skips_cloudwatch" {
  command = plan

  variables {
    logging_destination             = "s3"
    logging_bucket_creation_enabled = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 0 && length(aws_cloudwatch_log_delivery_source.access_logs) == 0 && length(aws_cloudwatch_log_delivery_destination.access_logs) == 0 && length(aws_cloudwatch_log_delivery.access_logs) == 0
    error_message = "No CloudWatch resources should be created when logging_destination is 's3'."
  }

  assert {
    condition     = length(aws_s3_bucket.logging) == 1
    error_message = "The S3 logging bucket must be created when logging_destination is 's3' and logging_bucket_creation_enabled is true."
  }
}

# Test: logging_enabled = false creates neither destination's resources
run "test_logging_disabled_creates_nothing" {
  command = plan

  variables {
    logging_enabled                 = false
    logging_bucket_creation_enabled = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 0 && length(aws_cloudwatch_log_delivery_source.access_logs) == 0 && length(aws_cloudwatch_log_delivery_destination.access_logs) == 0 && length(aws_cloudwatch_log_delivery.access_logs) == 0
    error_message = "No CloudWatch resources should be created when logging is disabled."
  }

  assert {
    condition     = length(aws_s3_bucket.logging) == 0
    error_message = "No S3 logging bucket should be created when logging is disabled, even with logging_bucket_creation_enabled = true."
  }
}

#-------------------------------------------------------------------------------
# Origin Access Control Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid origin_access_control_origin_type - s3 (default)
run "test_oac_origin_type_valid_s3" {
  command = plan

  assert {
    condition     = var.origin_access_control_origin_type == "s3"
    error_message = "s3 should be the default OAC origin type."
  }
}

# Test: Invalid origin_access_control_origin_type
run "test_oac_origin_type_invalid" {
  command = plan

  variables {
    origin_access_control_origin_type = "ec2"
  }

  expect_failures = [
    var.origin_access_control_origin_type,
  ]
}

# Test: Valid origin_access_control_signing_behavior - always (default)
run "test_oac_signing_behavior_valid_always" {
  command = plan

  assert {
    condition     = var.origin_access_control_signing_behavior == "always"
    error_message = "always should be the default signing behavior."
  }
}

# Test: Invalid origin_access_control_signing_behavior
run "test_oac_signing_behavior_invalid" {
  command = plan

  variables {
    origin_access_control_signing_behavior = "sometimes"
  }

  expect_failures = [
    var.origin_access_control_signing_behavior,
  ]
}

# Test: Invalid origin_access_control_signing_protocol
run "test_oac_signing_protocol_invalid" {
  command = plan

  variables {
    origin_access_control_signing_protocol = "sigv2"
  }

  expect_failures = [
    var.origin_access_control_signing_protocol,
  ]
}

#-------------------------------------------------------------------------------
# Custom Error Responses Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid custom_error_responses
run "test_custom_error_responses_valid" {
  command = plan

  variables {
    custom_error_responses = [
      {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"
      }
    ]
  }

  assert {
    condition     = length(var.custom_error_responses) == 1
    error_message = "Valid custom error response should be accepted."
  }
}

# Test: Invalid custom_error_responses - unsupported error code
run "test_custom_error_responses_invalid_code" {
  command = plan

  variables {
    custom_error_responses = [
      {
        error_code = 200
      }
    ]
  }

  expect_failures = [
    var.custom_error_responses,
  ]
}

#-------------------------------------------------------------------------------
# Edge Redirect Tests
#-------------------------------------------------------------------------------

run "test_redirect_rules_create_function" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "https://docs.example.com/:path*"
        destination = "https://www.example.com/docs/:path*"
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_function.redirect) == 1
    error_message = "A redirect function should be created when redirect rules are configured."
  }

  assert {
    condition     = aws_cloudfront_function.redirect[0].publish == true
    error_message = "The redirect function should be published."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect[0].code, "docs.example.com")
    error_message = "The redirect function code should contain the configured rules."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this["primary"].default_cache_behavior[0].function_association) == 1
    error_message = "The redirect function should be associated with the default cache behavior."
  }
}

run "test_redirect_rules_attach_to_ordered_behaviors" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "https://docs.example.com/:path*"
        destination = "https://www.example.com/docs/:path*"
      }
    ]
    ordered_cache_behaviors = [
      {
        path_pattern           = "/docs/*"
        target_origin_id       = "s3-origin"
        viewer_protocol_policy = "redirect-to-https"
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this["primary"].ordered_cache_behavior[0].function_association) == 1
    error_message = "The redirect function should be associated with every ordered cache behavior."
  }
}

run "test_redirect_rules_invalid_status" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old"
        destination = "/new"
        status_code = 303
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_invalid_source" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "docs"
        destination = "/new"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_invalid_destination" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old"
        destination = "http://www.example.com/new"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_reject_undefined_destination_parameter" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/:page"
        destination = "/new/:missing"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_reject_nonfinal_catch_all" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/:path*/edit"
        destination = "/new/:path*"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_reject_reserved_parameter" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/:__proto__"
        destination = "/new/:__proto__"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_reject_malformed_percent_escape" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/%invalid"
        destination = "/new"
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

run "test_redirect_rules_reject_function_conflict" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/:path*"
        destination = "/new/:path*"
      }
    ]
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "redirect-to-https"
      function_associations = [
        {
          event_type   = "viewer-request"
          function_arn = "arn:aws:cloudfront::123456789012:function/existing"
        }
      ]
    }
  }

  expect_failures = [
    aws_cloudfront_distribution.this["primary"],
  ]
}

run "test_redirect_rules_reject_ordered_lambda_conflict" {
  command = plan

  variables {
    redirect_rules = [
      {
        source      = "/old/:path*"
        destination = "/new/:path*"
      }
    ]
    ordered_cache_behaviors = [
      {
        path_pattern           = "/docs/*"
        target_origin_id       = "s3-origin"
        viewer_protocol_policy = "redirect-to-https"
        lambda_function_associations = [
          {
            event_type = "viewer-request"
            lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:existing:1"
          }
        ]
      }
    ]
  }

  expect_failures = [
    aws_cloudfront_distribution.this["primary"],
  ]
}

run "test_redirect_rules_reject_method_changing_non_read_redirect" {
  command = plan

  variables {
    redirect_rules = [
      {
        source                    = "/submit"
        destination               = "/new-submit"
        redirect_non_read_methods = true
        status_code               = 302
      }
    ]
  }

  expect_failures = [
    var.redirect_rules,
  ]
}

#-------------------------------------------------------------------------------
# Default Value Tests
#-------------------------------------------------------------------------------

# Test: All defaults
run "test_defaults" {
  command = plan

  assert {
    condition     = var.price_class == "PriceClass_100"
    error_message = "price_class should default to PriceClass_100."
  }

  assert {
    condition     = var.http_version == "http2and3"
    error_message = "http_version should default to http2and3."
  }

  assert {
    condition     = var.ipv6_enabled == true
    error_message = "ipv6_enabled should default to true."
  }

  assert {
    condition     = var.default_root_object == null
    error_message = "default_root_object should default to null."
  }

  assert {
    condition     = var.retain_on_delete_enabled == false
    error_message = "retain_on_delete_enabled should default to false."
  }

  assert {
    condition     = var.deployment_wait_enabled == true
    error_message = "deployment_wait_enabled should default to true."
  }

  assert {
    condition     = var.minimum_protocol_version == "TLSv1.2_2021"
    error_message = "minimum_protocol_version should default to TLSv1.2_2021."
  }

  assert {
    condition     = var.ssl_support_method == "sni-only"
    error_message = "ssl_support_method should default to sni-only."
  }

  assert {
    condition     = var.geo_restriction_type == "none"
    error_message = "geo_restriction_type should default to none."
  }

  assert {
    condition     = length(var.geo_restriction_locations) == 0
    error_message = "geo_restriction_locations should default to empty list."
  }

  assert {
    condition     = var.web_acl_id == null
    error_message = "web_acl_id should default to null."
  }

  assert {
    condition     = var.logging_enabled == true
    error_message = "logging_enabled should default to true (CloudWatch Logs delivery)."
  }

  assert {
    condition     = var.logging_destination == "cloudwatch"
    error_message = "logging_destination should default to cloudwatch."
  }

  assert {
    condition     = var.logging_bucket_creation_enabled == false
    error_message = "logging_bucket_creation_enabled should default to false."
  }

  assert {
    condition     = var.logging_bucket_retention_days == 90
    error_message = "logging_bucket_retention_days should default to 90."
  }

  assert {
    condition     = var.logging_cookies_enabled == false
    error_message = "logging_cookies_enabled should default to false."
  }

  assert {
    condition     = var.origin_access_control_creation_enabled == true
    error_message = "origin_access_control_creation_enabled should default to true."
  }

  assert {
    condition     = length(var.ordered_cache_behaviors) == 0
    error_message = "ordered_cache_behaviors should default to empty list."
  }

  assert {
    condition     = length(var.custom_error_responses) == 0
    error_message = "custom_error_responses should default to empty list."
  }

  assert {
    condition     = length(var.redirect_rules) == 0
    error_message = "redirect_rules should default to an empty list."
  }

  assert {
    condition     = length(aws_cloudfront_function.redirect) == 0
    error_message = "No redirect function should be created by default."
  }

  assert {
    condition     = var.default_cache_behavior.compression_enabled == true
    error_message = "compression_enabled should default to true in default_cache_behavior."
  }

  assert {
    condition     = length(var.default_cache_behavior.trusted_key_groups) == 0
    error_message = "trusted_key_groups should default to empty list in default_cache_behavior."
  }

  assert {
    condition     = var.accept_header_cache_policy_creation_enabled == false
    error_message = "accept_header_cache_policy_creation_enabled should default to false."
  }

  assert {
    condition     = length(aws_cloudfront_cache_policy.accept_header) == 0
    error_message = "The Accept-aware cache policy should not be created by default."
  }
}

run "test_accept_header_cache_policy_enabled" {
  command = plan

  variables {
    accept_header_cache_policy_creation_enabled = true
  }

  assert {
    condition     = length(aws_cloudfront_cache_policy.accept_header) == 1
    error_message = "The Accept-aware cache policy should be created when enabled."
  }

  assert {
    condition     = aws_cloudfront_distribution.this["primary"].default_cache_behavior[0].cache_policy_id == "accept-header-cache-policy-test"
    error_message = "The managed Accept-aware cache policy should be attached to the default behavior."
  }
}

run "test_accept_header_cache_policy_rejects_explicit_policy" {
  command = plan

  variables {
    accept_header_cache_policy_creation_enabled = true
    default_cache_behavior = {
      target_origin_id       = "s3-origin"
      viewer_protocol_policy = "redirect-to-https"
      cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    }
  }

  expect_failures = [
    var.accept_header_cache_policy_creation_enabled,
  ]
}
