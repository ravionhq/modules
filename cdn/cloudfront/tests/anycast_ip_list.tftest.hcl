mock_provider "aws" {
  mock_resource "aws_cloudfront_anycast_ip_list" {
    defaults = {
      id          = "test-static-ip-list"
      anycast_ips = ["192.0.2.1", "192.0.2.2", "192.0.2.3"]
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/ETEST"
    }
  }
}

mock_provider "ravion" {}

variables {
  name            = "test-cf"
  logging_enabled = false
  distributions = {
    primary   = {}
    secondary = {}
  }
  origins = [{
    origin_id   = "primary"
    domain_name = "origin.example.com"
  }]
  default_cache_behavior = {
    target_origin_id       = "primary"
    viewer_protocol_policy = "redirect-to-https"
  }
}

run "disabled_preserves_existing_defaults" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_anycast_ip_list.this) == 0 && output.anycast_ip_list_id == null && length(output.anycast_ips) == 0
    error_message = "No list or IP allocation should exist by default."
  }
  assert {
    condition     = alltrue([for d in aws_cloudfront_distribution.this : d.anycast_ip_list_id == null && d.is_ipv6_enabled && d.price_class == "PriceClass_100"])
    error_message = "Disabled static IPs must preserve the existing distribution settings."
  }
}

run "disabled_preserves_custom_settings" {
  command = plan
  variables {
    price_class  = "PriceClass_200"
    ipv6_enabled = false
  }
  assert {
    condition     = alltrue([for d in aws_cloudfront_distribution.this : !d.is_ipv6_enabled && d.price_class == "PriceClass_200"])
    error_message = "Disabled static IPs must preserve callers' price class and IPv6 overrides."
  }
}

run "create_shares_one_list_across_distributions" {
  command = apply

  variables {
    anycast_ip_list_mode = "create"
    tags                 = { Owner = "test" }
  }

  assert {
    condition     = length(aws_cloudfront_anycast_ip_list.this) == 1 && aws_cloudfront_anycast_ip_list.this[0].ip_count == 3
    error_message = "Create one list of three IPv4 addresses, not one per distribution."
  }
  assert {
    condition     = aws_cloudfront_anycast_ip_list.this[0].tags["Owner"] == "test"
    error_message = "The managed list must support caller tags."
  }
  assert {
    condition     = alltrue([for d in aws_cloudfront_distribution.this : d.anycast_ip_list_id == output.anycast_ip_list_id && !d.is_ipv6_enabled && d.price_class == "PriceClass_All"])
    error_message = "Both distributions must use the list with AWS-compatible IPv4 and all-edge settings."
  }
  assert {
    condition     = output.anycast_ip_list_id == "test-static-ip-list" && output.anycast_ips == tolist(["192.0.2.1", "192.0.2.2", "192.0.2.3"])
    error_message = "Return the list ID and allocated addresses."
  }
}

run "create_supports_allowlisting_count_and_long_names" {
  command = plan

  variables {
    name                 = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk"
    anycast_ip_list_mode = "create"
    anycast_ip_count     = 21
  }

  assert {
    condition     = aws_cloudfront_anycast_ip_list.this[0].ip_count == 21 && length(aws_cloudfront_anycast_ip_list.this[0].name) <= 64
    error_message = "Support the 21-IP allowlisting list without exceeding AWS's name limit."
  }
}

run "existing_list_is_not_managed" {
  command = plan

  variables {
    anycast_ip_list_mode = "existing"
    anycast_ip_list_id   = "  shared-list-id  "
  }

  assert {
    condition     = length(aws_cloudfront_anycast_ip_list.this) == 0 && output.anycast_ip_list_id == "shared-list-id" && length(output.anycast_ips) == 0
    error_message = "Reuse and normalize the existing list ID without owning its allocation."
  }
  assert {
    condition     = alltrue([for d in aws_cloudfront_distribution.this : d.anycast_ip_list_id == "shared-list-id" && !d.is_ipv6_enabled && d.price_class == "PriceClass_All"])
    error_message = "Reused lists must be attached to every distribution with compatible settings."
  }
}

run "managed_domains_use_static_ips" {
  command = plan

  variables {
    anycast_ip_list_mode  = "existing"
    anycast_ip_list_id    = "shared-list-id"
    module_instance_id    = "minst_test"
    ravion_aws_account_id = "aws_testaccount"
    distributions = {
      managed = { managed_domains = ["example.com"] }
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.managed["managed"].anycast_ip_list_id == "shared-list-id" && !aws_cloudfront_distribution.managed["managed"].is_ipv6_enabled && aws_cloudfront_distribution.managed["managed"].price_class == "PriceClass_All"
    error_message = "Ravion-managed certificates must use the same static IP wiring."
  }
}

run "reject_invalid_mode" {
  command = plan
  variables {
    anycast_ip_list_mode = "invalid"
  }
  expect_failures = [var.anycast_ip_list_mode]
}

run "reject_invalid_count" {
  command = plan
  variables {
    anycast_ip_list_mode = "create"
    anycast_ip_count     = 4
  }
  expect_failures = [var.anycast_ip_count]
}

run "reject_missing_existing_id" {
  command = plan
  variables {
    anycast_ip_list_mode = "existing"
  }
  expect_failures = [var.anycast_ip_list_id]
}

run "reject_blank_existing_id" {
  command = plan
  variables {
    anycast_ip_list_mode = "existing"
    anycast_ip_list_id   = " "
  }
  expect_failures = [var.anycast_ip_list_id]
}

run "reject_ambiguous_list_ownership" {
  command = plan
  variables {
    anycast_ip_list_mode = "create"
    anycast_ip_list_id   = "shared-list-id"
  }
  expect_failures = [var.anycast_ip_list_id]
}
