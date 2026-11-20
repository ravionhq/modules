# WAF module tests for the cloudfront target — run from module root: tofu test
#
# CloudFront only accepts global web ACLs created in us-east-1, whatever the
# provider's region. A distribution names its web ACL itself, so the module
# associates nothing and exposes the ARN instead.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test/12345678-1234-1234-1234-123456789012" }
  }
}

variables {
  name   = "test-cdn-waf"
  target = "cloudfront"
}

run "cloudfront_acl_is_global_in_us_east_1" {
  command = apply

  variables {
    # Ignored for CloudFront.
    region = "eu-west-1"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && output.scope == "CLOUDFRONT"
    error_message = "A cloudfront web ACL must have the CLOUDFRONT scope."
  }
  assert {
    condition     = aws_wafv2_web_acl.this.region == "us-east-1" && output.region == "us-east-1"
    error_message = "A cloudfront web ACL must be created in us-east-1 whatever the provider's or region input's region."
  }
  assert {
    condition     = length(aws_wafv2_web_acl_association.alb) == 0 && length(output.associated_alb_arns) == 0
    error_message = "A cloudfront web ACL must not be associated with load balancers."
  }
  assert {
    condition     = output.web_acl_arn == aws_wafv2_web_acl.this.arn
    error_message = "The web ACL ARN must be an output for the distribution to reference."
  }
}

run "cloudfront_acl_carries_the_same_rules" {
  command = apply

  variables {
    protected_paths   = ["/auth/signup"]
    bot_control_paths = ["/auth/signup"]
  }

  assert {
    condition     = [for r in sort([for r in aws_wafv2_web_acl.this.rule : format("%03d %s", r.priority, r.name)]) : split(" ", r)[1]] == ["aws-ip-reputation", "protected-paths-rate-limit", "aws-anonymous-ip", "aws-bot-control"]
    error_message = "A cloudfront web ACL must carry the same rules as an alb one."
  }
}

run "cloudfront_rejects_alb_arns" {
  command = plan

  variables {
    alb_arns = ["arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/public/0123456789abcdef"]
  }

  expect_failures = [var.alb_arns]
}

run "rejects_unknown_targets" {
  command = plan

  variables {
    target = "api-gateway"
  }

  expect_failures = [var.target]
}
