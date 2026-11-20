################################################################################
# hosting/static_site - origin_routes (same-origin API behind the SPA)
#
# A Vite SPA and an API on one domain: /v1/* must reach the API origin with
# its original URI while every other path keeps the SPA fallback.
################################################################################

mock_provider "ravion" {}

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

run "origin_routes_empty_by_default" {
  command = plan

  assert {
    condition     = length(local.origin_route_origins) == 0 && length(local.origin_route_behaviors) == 0
    error_message = "No extra origins or behaviors should exist without origin_routes."
  }

  assert {
    condition     = length(local.custom_error_responses) == 1 && local.custom_error_responses[0].response_page_path == "/404.html"
    error_message = "Without routes the static 404 page must stay wired."
  }
}

run "origin_routes_add_api_origin_and_behaviors" {
  command = plan

  variables {
    origin_routes = [
      {
        path_patterns = ["/v1", "/v1/*"]
        domain_name   = "api-123.us-east-1.elb.amazonaws.com"
        custom_headers = [
          { name = "X-Origin-Auth", value = "secret" },
        ]
      },
    ]
  }

  assert {
    condition     = length(local.origin_route_origins) == 1 && local.origin_route_origins[0].origin_id == "route-0"
    error_message = "Each route must create one custom origin."
  }

  assert {
    condition     = local.origin_route_origins[0].origin_protocol_policy == "https-only"
    error_message = "Route origins must default to HTTPS only."
  }

  assert {
    condition     = [for b in local.ordered_behaviors : b.path_pattern] == ["/v1", "/v1/*"]
    error_message = "Each path pattern must become one ordered behavior, ahead of any other behaviors, and the error-document behavior must be dropped."
  }

  assert {
    condition     = alltrue([for b in local.origin_route_behaviors : b.target_origin_id == "route-0" && length(b.function_associations) == 0])
    error_message = "Route behaviors must target the route origin without the version rewrite or Cache-Control functions."
  }

  assert {
    condition     = alltrue([for b in local.origin_route_behaviors : length(b.allowed_methods) == 7 && b.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" && b.origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac"])
    error_message = "Route behaviors must default to all methods, CachingDisabled, and AllViewerExceptHostHeader."
  }

  assert {
    condition     = alltrue([for r in local.custom_error_responses : r.response_page_path == null && r.response_code == null && r.error_caching_min_ttl == 0])
    error_message = "With routes, error responses must pass through uncached so API errors are never replaced or shared."
  }

  assert {
    condition     = contains([for r in local.custom_error_responses : r.error_code], 404) && contains([for r in local.custom_error_responses : r.error_code], 403)
    error_message = "With routes, 403 and 404 error caching must be disabled."
  }
}

run "origin_routes_multiple_routes_get_distinct_origins" {
  command = plan

  variables {
    origin_routes = [
      { path_patterns = ["/v1/*"], domain_name = "api.example.com" },
      {
        path_patterns          = ["/auth/*"]
        domain_name            = "auth.example.com"
        origin_path            = "/prod"
        origin_protocol_policy = "http-only"
        allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      },
    ]
  }

  assert {
    condition     = [for o in local.origin_route_origins : o.origin_id] == ["route-0", "route-1"]
    error_message = "Each route must get its own origin ID."
  }

  assert {
    condition     = [for b in local.origin_route_behaviors : b.target_origin_id] == ["route-0", "route-1"]
    error_message = "Each behavior must target its route's origin."
  }

  assert {
    condition     = local.origin_route_origins[1].origin_path == "/prod" && join(",", local.origin_route_behaviors[1].allowed_methods) == "GET,HEAD,OPTIONS"
    error_message = "Per-route overrides must flow through."
  }
}

run "origin_routes_rejects_catch_all" {
  command = plan

  variables {
    origin_routes = [{ path_patterns = ["/*"], domain_name = "api.example.com" }]
  }

  expect_failures = [var.origin_routes]
}

run "origin_routes_rejects_duplicate_patterns" {
  command = plan

  variables {
    origin_routes = [
      { path_patterns = ["/v1/*"], domain_name = "api.example.com" },
      { path_patterns = ["/v1/*"], domain_name = "other.example.com" },
    ]
  }

  expect_failures = [var.origin_routes]
}

run "origin_routes_rejects_url_domain" {
  command = plan

  variables {
    origin_routes = [{ path_patterns = ["/v1/*"], domain_name = "https://api.example.com" }]
  }

  expect_failures = [var.origin_routes]
}

run "origin_routes_rejects_empty_patterns" {
  command = plan

  variables {
    origin_routes = [{ path_patterns = [], domain_name = "api.example.com" }]
  }

  expect_failures = [var.origin_routes]
}

run "origin_routes_rejects_invalid_method_combo" {
  command = plan

  variables {
    origin_routes = [{ path_patterns = ["/v1/*"], domain_name = "api.example.com", allowed_methods = ["GET", "POST"] }]
  }

  expect_failures = [var.origin_routes]
}
