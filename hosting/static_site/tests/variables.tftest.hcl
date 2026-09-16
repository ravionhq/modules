################################################################################
# hosting/static_site - Variable validation and Cache-Control wiring tests
#
# Variable validation rules cover input shape; the Cache-Control section
# verifies that the viewer-response CloudFront Function (added in ENG-4785) is
# wired up correctly and that its template substitutions reach the function
# body. Child-module behavior (storage/s3, cdn/cloudfront) is exercised by the
# per-module tests under their own `tests/` directories.
################################################################################

mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.hosting_bucket_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.deploy_role_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# CloudFront distribution, KVS, CloudFront Functions, and the optional
# response-headers policy all run through the us_east_1 alias. Their resource
# overrides live here so apply-mode tests don't hit the real CloudFront API
# and so resource arns are deterministic.
mock_provider "aws" {
  alias = "us_east_1"

  override_resource {
    target = aws_cloudfront_function.rewrite
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-rewrite"
    }
  }

  override_resource {
    target = aws_cloudfront_function.cache_control
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-cache-control"
    }
  }

  override_resource {
    target = aws_cloudfront_key_value_store.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:key-value-store/12345678-1234-1234-1234-123456789012"
      id  = "12345678-1234-1234-1234-123456789012"
    }
  }

  override_resource {
    target = aws_cloudfront_response_headers_policy.this
    values = {
      id = "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  override_resource {
    target = aws_cloudfront_cache_policy.this
    values = {
      id = "module-cache-policy-11111111-2222-3333-4444-555555555555"
    }
  }

  # The delivery-source and delivery-destination resources validate their ARN
  # attributes at plan time, so mocked upstream ARNs must be well-formed.
  override_resource {
    target = module.cdn.aws_cloudfront_distribution.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE123"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_group.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/ravion-test-site"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_delivery_destination.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:ravion-test-site-access-logs-cw"
    }
  }
}

variables {
  name = "ravion-test-site"
}

#-------------------------------------------------------------------------------
# Routing validation
#-------------------------------------------------------------------------------

run "routing_default_is_spa" {
  command = plan

  assert {
    condition     = var.routing == "spa"
    error_message = "routing should default to 'spa'."
  }
}

run "routing_accepts_filesystem" {
  command = plan

  variables {
    routing = "filesystem"
  }

  assert {
    condition     = var.routing == "filesystem"
    error_message = "routing should accept 'filesystem'."
  }
}

run "routing_rejects_unknown" {
  command = plan

  variables {
    routing = "ssr"
  }

  expect_failures = [var.routing]
}

#-------------------------------------------------------------------------------
# default_version validation
#-------------------------------------------------------------------------------

run "default_version_default_is_main" {
  command = plan

  assert {
    condition     = var.default_version == "main"
    error_message = "default_version should default to 'main'."
  }
}

run "default_version_accepts_single_segment" {
  command = plan

  variables {
    default_version = "v_2026-07-10.1"
  }

  assert {
    condition     = var.default_version == "v_2026-07-10.1"
    error_message = "default_version should accept single-segment names with letters, numbers, '.', '_', '-'."
  }
}

run "default_version_rejects_multi_segment" {
  command = plan

  variables {
    default_version = "versions/v1"
  }

  # Multi-segment versions would break the cache-control function, which
  # strips exactly one leading path segment to recover the viewer-facing path.
  expect_failures = [var.default_version]
}

run "default_version_rejects_invalid_chars" {
  command = plan

  variables {
    default_version = "v 1!"
  }

  expect_failures = [var.default_version]
}

run "kvs_initial_data_rejects_multi_segment_versions" {
  command = plan

  variables {
    kvs_initial_data = {
      "staging.example.com" = "versions/v1"
    }
  }

  expect_failures = [var.kvs_initial_data]
}

#-------------------------------------------------------------------------------
# Name validation (S3 bucket name rules)
#-------------------------------------------------------------------------------

run "name_rejects_uppercase" {
  command = plan

  variables {
    name = "Ravion-Test-Site"
  }

  expect_failures = [var.name]
}

run "name_rejects_underscores" {
  command = plan

  variables {
    name = "ravion_test_site"
  }

  expect_failures = [var.name]
}

run "name_rejects_too_short" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "name_rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-ravion"
  }

  expect_failures = [var.name]
}

run "request_rewrite_name_avoids_legacy_collision" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = local.cff_request_rewrite_name != substr(replace("${var.name}-rewrite", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
    error_message = "The replacement rewrite function name must differ from the legacy name for long site names."
  }

  assert {
    condition     = length(local.cff_request_rewrite_name) <= 64 && endswith(local.cff_request_rewrite_name, "-request-rewrite")
    error_message = "The replacement rewrite function name must fit CloudFront's 64-character limit and retain its collision-free suffix."
  }

  assert {
    condition     = strcontains(local.cff_request_rewrite_name, substr(sha1(var.name), 0, 8))
    error_message = "The replacement rewrite function name must hash the full site name so names that share a truncated prefix remain unique."
  }
}

#-------------------------------------------------------------------------------
# Distributions
#-------------------------------------------------------------------------------

run "distributions_default_to_main" {
  command = plan

  assert {
    condition     = contains(keys(var.distributions), "main")
    error_message = "distributions should default to a 'main' entry."
  }
}

run "distributions_rejects_empty" {
  command = plan

  variables {
    distributions = {}
  }

  expect_failures = [var.distributions]
}

#-------------------------------------------------------------------------------
# Geo restrictions
#-------------------------------------------------------------------------------

run "geo_restriction_type_rejects_invalid" {
  command = plan

  variables {
    geo_restriction_type = "deny"
  }

  expect_failures = [var.geo_restriction_type]
}

#-------------------------------------------------------------------------------
# WAF
#-------------------------------------------------------------------------------

run "web_acl_id_rejects_non_wafv2" {
  command = plan

  variables {
    web_acl_id = "arn:aws:waf::123456789012:webacl/my-acl"
  }

  expect_failures = [var.web_acl_id]
}

run "web_acl_id_accepts_valid_arn" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"
  }

  assert {
    condition     = var.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc-123"
    error_message = "Valid WAFv2 ARN should be accepted."
  }
}

#-------------------------------------------------------------------------------
# KMS
#-------------------------------------------------------------------------------

run "kms_key_arn_rejects_invalid" {
  command = plan

  variables {
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

#-------------------------------------------------------------------------------
# Deploy role
#-------------------------------------------------------------------------------

run "deploy_role_trust_policy_rejects_invalid_json" {
  command = plan

  variables {
    deploy_role_trust_policy = "not json {{"
  }

  expect_failures = [var.deploy_role_trust_policy]
}

#-------------------------------------------------------------------------------
# Cache-Control wiring (ENG-4785)
#
# A viewer-response CloudFront Function classifies every response by the
# rewritten URI shape and writes Cache-Control accordingly. The previous
# response-headers-policy approach could not see the rewritten URI, which is
# why SPA routes like `/dashboard` ended up with the immutable-assets header.
# These tests pin down: defaults, opt-out toggle, header values reaching the
# function body, override list reaching the function body, and the function
# being attached to every cache behavior.
#-------------------------------------------------------------------------------

run "cache_control_defaults" {
  command = plan

  assert {
    condition     = var.cache_control_enabled == true
    error_message = "cache_control_enabled should default to true."
  }

  assert {
    condition     = var.html_cache_control == "public, max-age=0, must-revalidate"
    error_message = "html_cache_control should default to browser revalidate-always — the header only steers the browser (CloudFront ignores viewer-response headers for edge TTLs), and max-age=0 + must-revalidate makes version flips visible on the first navigation."
  }

  assert {
    condition     = var.assets_cache_control == "public, max-age=31536000, immutable"
    error_message = "assets_cache_control should default to a 1-year immutable browser cache."
  }

  assert {
    condition     = contains(var.html_path_overrides, "/service-worker.js") && contains(var.html_path_overrides, "/favicon.ico") && contains(var.html_path_overrides, "/robots.txt")
    error_message = "html_path_overrides defaults must include service-worker, favicon, and robots.txt to keep stable root files off the immutable cache."
  }
}

run "cache_control_function_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 1
    error_message = "viewer-response cache-control function must be created when cache_control_enabled = true."
  }

  assert {
    condition     = length(local.cff_associations) == 2
    error_message = "Both the viewer-request rewriter and the viewer-response cache-control function must be associated with cache behaviors."
  }

  assert {
    condition     = local.cff_associations[0].event_type == "viewer-request" && local.cff_associations[1].event_type == "viewer-response"
    error_message = "viewer-request must run before viewer-response so cache-control sees the rewritten URI shape."
  }
}

run "cache_control_function_body_carries_template_values" {
  command = plan

  assert {
    condition     = strcontains(local.cff_cache_control_code, "public, max-age=0, must-revalidate")
    error_message = "html_cache_control value must be substituted into the viewer-response function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "public, max-age=31536000, immutable")
    error_message = "assets_cache_control value must be substituted into the viewer-response function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "/service-worker.js") && strcontains(local.cff_cache_control_code, "/favicon.ico")
    error_message = "html_path_overrides entries must be substituted into the viewer-response function body so non-hashed root files don't get cached as immutable."
  }
}

run "cache_control_custom_overrides_flow_into_function" {
  command = plan

  variables {
    html_cache_control   = "no-store"
    assets_cache_control = "public, max-age=600"
    html_path_overrides  = ["/custom.txt", "/another.bin"]
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "no-store")
    error_message = "Caller override of html_cache_control must reach the function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "public, max-age=600")
    error_message = "Caller override of assets_cache_control must reach the function body."
  }

  assert {
    condition     = strcontains(local.cff_cache_control_code, "/custom.txt") && strcontains(local.cff_cache_control_code, "/another.bin")
    error_message = "Caller override of html_path_overrides must reach the function body."
  }
}

run "cache_control_disabled_skips_function" {
  command = plan

  variables {
    cache_control_enabled = false
  }

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 0
    error_message = "viewer-response cache-control function must NOT be created when cache_control_enabled = false."
  }

  assert {
    condition     = length(local.cff_associations) == 1
    error_message = "Only the viewer-request rewriter must be associated when cache_control_enabled = false."
  }

  assert {
    condition     = local.cff_associations[0].event_type == "viewer-request"
    error_message = "The remaining association must be the viewer-request rewriter."
  }
}

#-------------------------------------------------------------------------------
# Response-headers policy (security headers, CORS, custom headers)
#
# The module-managed policy is created on demand from var.response_headers_policy
# and carries security headers / CORS / arbitrary custom headers — Cache-Control
# stays the cache-control function's job. var.response_headers_policy_id remains
# as the override for callers with a centrally-managed policy.
#-------------------------------------------------------------------------------

run "response_headers_policy_defaults_to_managed_security_headers" {
  command = plan

  assert {
    condition     = var.response_headers_policy == null
    error_message = "response_headers_policy must default to null so basic deployments don't allocate an unused policy resource."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "No module-managed response-headers policy should be created when response_headers_policy is null."
  }

  assert {
    condition     = tolist(var.response_headers_presets) == tolist(["security_headers"])
    error_message = "response_headers_presets should default to ['security_headers']."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    error_message = "Default behavior should attach the AWS-managed SecurityHeadersPolicy when neither response_headers_policy nor response_headers_policy_id is set."
  }
}

run "response_headers_presets_empty_attaches_no_policy" {
  command = plan

  variables {
    response_headers_presets = []
  }

  assert {
    condition     = local.effective_response_headers_policy_id == null
    error_message = "No response-headers policy should be attached when response_headers_presets is empty and no caller policy is set."
  }
}

run "response_headers_presets_map_to_managed_combo_policies" {
  command = plan

  variables {
    response_headers_presets = ["security_headers", "cors"]
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "e61eb60c-9c35-4d20-a928-2b84e02af89c"
    error_message = "security_headers + cors must map to the AWS-managed CORS-and-SecurityHeadersPolicy — CloudFront only allows one response-headers policy per behavior, so combinations resolve to the managed combo policy."
  }
}

run "response_headers_presets_preflight_supersedes_cors" {
  command = plan

  variables {
    response_headers_presets = ["cors", "cors_preflight", "security_headers"]
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "eaab4381-ed33-4a86-88ca-d9558dc6cd63"
    error_message = "cors_preflight + security_headers (with or without redundant 'cors') must map to CORS-with-preflight-and-SecurityHeadersPolicy."
  }
}

run "response_headers_presets_cors_only" {
  command = plan

  variables {
    response_headers_presets = ["cors"]
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "60669652-455b-4ae9-85a4-c4c02393f86c"
    error_message = "cors alone must map to the AWS-managed SimpleCORS policy."
  }
}

run "response_headers_presets_preflight_only" {
  command = plan

  variables {
    response_headers_presets = ["cors_preflight"]
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "5cc3b908-e619-4b99-88e5-2cf7f45965bd"
    error_message = "cors_preflight alone must map to the AWS-managed CORS-With-Preflight policy."
  }
}

run "response_headers_presets_reject_unknown_values" {
  command = plan

  variables {
    response_headers_presets = ["security_headers", "csp"]
  }

  expect_failures = [var.response_headers_presets]
}

run "response_headers_policy_creates_resource_when_set" {
  command = apply

  variables {
    response_headers_policy = {
      security_headers_config = {
        strict_transport_security = {
          access_control_max_age_sec = 63072000
          include_subdomains         = true
          preload                    = true
        }
        content_security_policy = {
          content_security_policy = "default-src 'self'"
        }
        content_type_options = {}
        frame_options = {
          frame_option = "DENY"
        }
        referrer_policy = {
          referrer_policy = "strict-origin-when-cross-origin"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Setting response_headers_policy.security_headers_config must create the module-managed policy."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "The default behavior must attach the module-managed policy id when response_headers_policy is set and response_headers_policy_id is not."
  }
}

run "response_headers_policy_supports_cors_custom_and_remove_headers" {
  command = apply

  variables {
    response_headers_policy = {
      cors_config = {
        access_control_allow_credentials = false
        access_control_allow_headers     = ["Content-Type", "Authorization"]
        access_control_allow_methods     = ["GET", "HEAD", "OPTIONS"]
        access_control_allow_origins     = ["https://app.example.com"]
        access_control_expose_headers    = ["X-Request-Id"]
        access_control_max_age_sec       = 600
      }
      custom_headers = [
        {
          header = "Permissions-Policy"
          value  = "camera=(), microphone=()"
        },
        {
          header = "Cross-Origin-Opener-Policy"
          value  = "same-origin"
        },
      ]
      remove_headers = ["Server", "X-Powered-By"]
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Setting response_headers_policy with cors / custom_headers / remove_headers must create the policy."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 1
    error_message = "cors_config block must be present on the policy when var.response_headers_policy.cors_config is set."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].custom_headers_config) == 1
    error_message = "custom_headers_config block must be present when var.response_headers_policy.custom_headers is non-empty."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].remove_headers_config) == 1
    error_message = "remove_headers_config block must be present when var.response_headers_policy.remove_headers is non-empty."
  }
}

run "response_headers_policy_skips_unset_blocks" {
  command = apply

  variables {
    response_headers_policy = {
      security_headers_config = {
        content_type_options = {}
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config) == 1
    error_message = "security_headers_config block must be present when set on the variable."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].cors_config) == 0
    error_message = "cors_config block must NOT be created when the variable's cors_config field is null."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].custom_headers_config) == 0
    error_message = "custom_headers_config block must NOT be created when custom_headers is empty."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].remove_headers_config) == 0
    error_message = "remove_headers_config block must NOT be created when remove_headers is empty."
  }
}

run "response_headers_policy_id_overrides_module_managed" {
  command = apply

  variables {
    response_headers_policy_id = "11111111-2222-3333-4444-555555555555"
    response_headers_policy = {
      security_headers_config = {
        content_type_options = {}
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "The module-managed policy is still created — the output remains available for use elsewhere."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "11111111-2222-3333-4444-555555555555"
    error_message = "When both response_headers_policy_id and response_headers_policy are set, the caller-supplied id wins on the default behavior."
  }
}

run "response_headers_policy_validates_frame_option" {
  command = plan

  variables {
    response_headers_policy = {
      security_headers_config = {
        frame_options = {
          frame_option = "ALLOW"
        }
      }
    }
  }

  expect_failures = [var.response_headers_policy]
}

#-------------------------------------------------------------------------------
# Origin Shield region derivation
#
# origin_shield_enabled is a plain boolean; the shield region is derived from
# the bucket region — same region when CloudFront offers Origin Shield there,
# otherwise the nearest supported region per the AWS mapping table.
# origin_shield_region overrides the derivation.
#-------------------------------------------------------------------------------

run "origin_shield_disabled_by_default" {
  command = plan

  assert {
    condition     = var.origin_shield_enabled == false
    error_message = "origin_shield_enabled should default to false."
  }
}

run "origin_shield_same_region_when_supported" {
  command = plan

  variables {
    region = "eu-west-1"
  }

  assert {
    condition     = local.origin_shield_region == "eu-west-1"
    error_message = "Buckets in a region where CloudFront offers Origin Shield must shield in the same region."
  }
}

run "origin_shield_nearest_region_when_unsupported" {
  command = plan

  variables {
    region = "ca-central-1"
  }

  assert {
    condition     = local.origin_shield_region == "us-east-1"
    error_message = "Buckets in ca-central-1 must shield in us-east-1 per the AWS nearest-region mapping."
  }
}

run "origin_shield_explicit_region_overrides_derivation" {
  command = plan

  variables {
    region               = "eu-west-1"
    origin_shield_region = "us-east-2"
  }

  assert {
    condition     = local.origin_shield_region == "us-east-2"
    error_message = "An explicit origin_shield_region must override the derived region."
  }
}

#-------------------------------------------------------------------------------
# Primary domain output
#-------------------------------------------------------------------------------

run "primary_domain_uses_first_alias_when_set" {
  command = apply

  variables {
    distributions = {
      main = {
        aliases             = ["app.example.com", "www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
      }
    }
  }

  assert {
    condition     = output.primary_domain == "app.example.com"
    error_message = "primary_domain must be the first alias when aliases are configured."
  }
}

run "primary_domain_falls_back_to_cloudfront_domain" {
  command = apply

  assert {
    condition     = output.primary_domain == module.cdn.distribution_domain_names["main"]
    error_message = "primary_domain must fall back to the CloudFront domain name when no aliases are configured."
  }

  assert {
    condition     = output.primary_distribution_id == module.cdn.distribution_ids["main"]
    error_message = "primary_distribution_id must be the primary distribution's ID."
  }
}

#-------------------------------------------------------------------------------
# Access logging (delegated to cdn/cloudfront)
#
# The CloudWatch standard-logging-v2 delivery chain lives inside module.cdn,
# whose resources are not addressable from run-block assertions, so behavior
# is pinned through the module outputs in apply mode. Resource-level chain
# assertions live in cdn/cloudfront's own tests.
#-------------------------------------------------------------------------------

run "logging_enabled_by_default_exposes_log_group" {
  command = apply

  assert {
    condition     = output.access_log_group_name == "/aws/cloudfront/ravion-test-site"
    error_message = "Logging defaults to enabled with the CloudWatch destination, so the access-log group output must be the module-managed group name."
  }

  assert {
    condition     = output.access_log_group_arn != null
    error_message = "The access-log group ARN output must be set when CloudWatch logging is active."
  }
}

run "logging_disabled_creates_no_cloudwatch_resources" {
  command = apply

  variables {
    logging_enabled = false
  }

  assert {
    condition     = output.access_log_group_name == null && output.access_log_group_arn == null
    error_message = "No CloudWatch log group should be created when logging is disabled."
  }
}

run "s3_logging_destination_skips_cloudwatch" {
  command = apply

  variables {
    logging_enabled                 = true
    logging_destination             = "s3"
    logging_bucket_creation_enabled = true
  }

  assert {
    condition     = output.access_log_group_name == null && output.access_log_group_arn == null
    error_message = "No CloudWatch resources should be created when logging_destination is 's3'."
  }
}

run "logging_destination_rejects_unknown" {
  command = plan

  variables {
    logging_destination = "firehose"
  }

  expect_failures = [var.logging_destination]
}

run "logging_retention_days_defaults_to_365" {
  command = plan

  assert {
    condition     = var.logging_retention_days == 365
    error_message = "logging_retention_days should default to 365."
  }
}

run "cloudwatch_retention_rejects_invalid_value" {
  command = plan

  variables {
    logging_enabled        = true
    logging_retention_days = 45
  }

  expect_failures = [var.logging_retention_days]
}

#-------------------------------------------------------------------------------
# Cache policy (module-managed 1-year edge TTL)
#-------------------------------------------------------------------------------

run "cache_policy_defaults_to_module_managed_one_year" {
  command = plan

  assert {
    condition     = var.cache_policy_id == null
    error_message = "cache_policy_id should default to null so the module-managed 1-year policy is used."
  }

  assert {
    condition     = length(aws_cloudfront_cache_policy.this) == 1
    error_message = "The module-managed cache policy must be created when cache_policy_id is null."
  }

  assert {
    condition     = aws_cloudfront_cache_policy.this[0].default_ttl == 31536000 && aws_cloudfront_cache_policy.this[0].max_ttl == 31536000
    error_message = "The module-managed cache policy must cache at the edge for up to 1 year - S3 sends no Cache-Control, so the default TTL governs edge lifetime, and versioned cache keys make long TTLs safe."
  }
}

run "cache_policy_id_override_skips_module_policy" {
  command = plan

  variables {
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  assert {
    condition     = length(aws_cloudfront_cache_policy.this) == 0
    error_message = "No module-managed cache policy should be created when the caller supplies cache_policy_id."
  }

  assert {
    condition     = local.effective_cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "The caller-supplied cache policy ID must be attached to the default behavior."
  }
}

#-------------------------------------------------------------------------------
# 404 handling (error_document)
#
# Missing objects return real 404s because the bucket policy grants CloudFront
# s3:ListBucket. The 404 custom error response is always emitted so
# error_caching_min_ttl always applies; the response page is only attached
# when error_document is set (default '404.html'), serving it as the 404 body
# while keeping the 404 status. The error-page fetch bypasses the
# viewer-request rewrite, so the key resolves at the bucket root — deploys
# copy <version>/404.html there at promotion.
#-------------------------------------------------------------------------------

run "error_document_default_wires_custom_error_response" {
  command = plan

  assert {
    condition     = var.error_document == "404.html"
    error_message = "error_document should default to '404.html'."
  }

  assert {
    condition     = length(local.custom_error_responses) == 1
    error_message = "Exactly one custom error response should be configured when error_document is set."
  }

  assert {
    condition     = local.custom_error_responses[0].error_code == 404 && local.custom_error_responses[0].response_code == 404
    error_message = "The custom error response must keep the real 404 status — never rewrite it to 200 (SEO) and never map 403 (a 403 now only means blocked, e.g. WAF)."
  }

  assert {
    condition     = local.custom_error_responses[0].response_page_path == "/404.html"
    error_message = "The response page path must be the bucket-root key derived from error_document."
  }

  assert {
    condition     = local.custom_error_responses[0].error_caching_min_ttl == 86400
    error_message = "error_caching_min_ttl should default to 86400 seconds (1 day) — versioned deploys make cached 404s safe."
  }
}

run "error_document_empty_serves_plain_404s_with_ttl" {
  command = plan

  variables {
    error_document        = ""
    error_caching_min_ttl = 0
  }

  assert {
    condition     = length(local.custom_error_responses) == 1
    error_message = "The 404 custom error response must still be emitted when error_document is empty so error_caching_min_ttl is never silently ignored."
  }

  assert {
    condition     = local.custom_error_responses[0].response_page_path == null
    error_message = "No response page must be attached when error_document is empty — viewers get the plain 404."
  }

  assert {
    condition     = local.custom_error_responses[0].error_caching_min_ttl == 0
    error_message = "error_caching_min_ttl must apply even when the custom error page is disabled."
  }
}

run "error_document_null_falls_back_to_default" {
  command = plan

  variables {
    error_document = null
  }

  assert {
    condition     = local.custom_error_responses[0].response_page_path == "/404.html"
    error_message = "Passing null must apply the default '404.html' (nullable = false), so definition-layer nils never silently disable the error page."
  }
}

run "error_document_rejects_leading_slash" {
  command = plan

  variables {
    error_document = "/404.html"
  }

  expect_failures = [var.error_document]
}

run "error_caching_min_ttl_rejects_out_of_range" {
  command = plan

  variables {
    error_caching_min_ttl = 31536001
  }

  expect_failures = [var.error_caching_min_ttl]
}

run "error_document_gets_no_cache_behavior" {
  command = plan

  assert {
    condition     = length([for b in local.ordered_behaviors : b if b.path_pattern == "/404.html"]) == 1
    error_message = "A dedicated cache behavior must pin the error document to CachingDisabled so a changed 404 page is never edge-cached for the long default TTL."
  }

  assert {
    condition     = [for b in local.ordered_behaviors : b.cache_policy_id if b.path_pattern == "/404.html"][0] == local.managed_cache_disabled_id
    error_message = "The error-document behavior must use the managed CachingDisabled policy."
  }
}

run "error_document_empty_adds_no_behavior" {
  command = plan

  variables {
    error_document = ""
  }

  assert {
    condition     = length(local.ordered_behaviors) == 0
    error_message = "No error-document behavior should exist when the error page is disabled."
  }
}

run "response_headers_policy_id_alone_works_without_module_policy" {
  command = apply

  variables {
    response_headers_policy_id = "22222222-3333-4444-5555-666666666666"
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "When only response_headers_policy_id is set, no module-managed policy resource should be created."
  }

  assert {
    condition     = local.effective_response_headers_policy_id == "22222222-3333-4444-5555-666666666666"
    error_message = "The caller-supplied id must be attached to the default behavior."
  }

  assert {
    condition     = length(aws_cloudfront_function.cache_control) == 1
    error_message = "The cache-control function must coexist with a caller-supplied response-headers policy — they handle orthogonal concerns."
  }
}
