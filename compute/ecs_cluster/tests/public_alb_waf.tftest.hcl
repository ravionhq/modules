# Public ALB WAF association tests
#
# Setting public_alb_web_acl_arn must associate the Web ACL with the public ALB.
# The ALB module only creates the association when waf_association_enabled is
# true, so the cluster module has to derive that flag from the ARN.
#
# Run with: tofu test -filter=tests/public_alb_waf.tftest.hcl

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" {
    defaults = { id = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::127311923021:root" }
  }
  # Listeners and WAF associations validate the load balancer ARN they are handed.
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/0123456789abcdef" }
  }
}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
  public_alb_enabled = true
  public_subnet_ids  = ["subnet-public1", "subnet-public2"]
}

run "public_alb_without_web_acl_skips_waf_association" {
  command = plan

  assert {
    condition     = module.public_alb[0].web_acl_arn == null
    error_message = "The public ALB must not be associated with a WAF web ACL when public_alb_web_acl_arn is unset."
  }
}

run "public_alb_web_acl_arn_associates_waf" {
  command = plan

  variables {
    public_alb_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = module.public_alb[0].web_acl_arn == "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/12345678-1234-1234-1234-123456789012"
    error_message = "Setting public_alb_web_acl_arn must associate that WAF web ACL with the public ALB."
  }
}
