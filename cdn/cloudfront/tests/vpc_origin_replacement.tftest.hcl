################################################################################
# VPC Origin Replacement Tests
#
# CloudFront rejects updates to a VPC origin that a distribution uses, so the
# VPC origin is replaced (create before destroy) whenever
# terraform_data.vpc_origin_endpoint changes. These runs check that the trigger
# tracks every endpoint setting and that each endpoint configuration gets its
# own name, so the replacement can exist alongside the VPC origin it replaces.
################################################################################

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
      arn = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
    }
  }

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

variables {
  name = "test-cf"
  distributions = {
    primary = {}
  }
  origins = [
    {
      origin_id              = "alb-origin"
      domain_name            = "website.private.example.com"
      vpc_origin_enabled     = true
      vpc_origin_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/1111111111111111"
      origin_protocol_policy = "https-only"
    }
  ]
  default_cache_behavior = {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
  }
}

run "replacement_trigger_tracks_every_endpoint_setting" {
  command = plan

  assert {
    condition     = toset(keys(terraform_data.vpc_origin_endpoint["alb-origin"].input)) == toset(["arn", "http_port", "https_port", "origin_protocol_policy", "origin_ssl_protocols", "base_name"])
    error_message = "The replacement trigger must include the load balancer, ports, protocol settings and name of the VPC origin endpoint."
  }

  assert {
    condition = alltrue([
      terraform_data.vpc_origin_endpoint["alb-origin"].input.arn == aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].arn,
      terraform_data.vpc_origin_endpoint["alb-origin"].input.http_port == aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].http_port,
      terraform_data.vpc_origin_endpoint["alb-origin"].input.https_port == aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].https_port,
      terraform_data.vpc_origin_endpoint["alb-origin"].input.origin_protocol_policy == aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].origin_protocol_policy,
      toset(terraform_data.vpc_origin_endpoint["alb-origin"].input.origin_ssl_protocols) == toset(aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].origin_ssl_protocols[0].items),
    ])
    error_message = "The replacement trigger must carry the same endpoint settings the VPC origin is created with."
  }
}

run "name_follows_the_endpoint_configuration" {
  command = plan

  assert {
    condition     = aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].name == "test-cf-alb-origin-${substr(sha1(jsonencode(terraform_data.vpc_origin_endpoint["alb-origin"].input)), 0, 8)}"
    error_message = "The VPC origin name must carry a hash of its endpoint configuration, so a replacement never reuses the name of the VPC origin it replaces."
  }

  assert {
    condition     = aws_cloudfront_vpc_origin.this["alb-origin"].tags["Name"] == "test-cf-alb-origin"
    error_message = "The Name tag should stay the readable module name and origin ID."
  }
}

run "long_names_stay_within_the_vpc_origin_name_limit" {
  command = plan

  variables {
    name = "a-very-long-cloudfront-module-name-that-fills-most-of-the-limit"
  }

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this["alb-origin"].vpc_origin_endpoint_config[0].name) <= 64
    error_message = "VPC origin names must stay within 64 characters."
  }
}
