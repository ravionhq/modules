################################################################################
# Target group names
#
# ELBv2 accepts only alphanumerics and hyphens in target group names, while
# var.name also permits underscores because it names the ECS service and seeds
# the ECR repository. Every target group this module creates (the ALB
# production/alternate pair and the per-listener NLB groups) must therefore
# never carry an underscore, whether the name is kept whole or truncated.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
  mock_data "aws_lb_listener" {
    defaults = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock-alb/1234567890123456"
    }
  }
  mock_data "aws_lb" {
    defaults = {
      dns_name = "mock-alb-1234567890.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
    }
  }

  # Computed ARNs must look like real ARNs to pass provider-side
  # validation on referencing resources (task definition, listener
  # rules, advanced_configuration).
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock-tg/1234567890123456"
      arn_suffix = "targetgroup/mock-tg/1234567890123456"
    }
  }
  mock_resource "aws_lb_listener_rule" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/mock-alb/1234567890123456/1234567890123456/1234567890123456"
    }
  }
  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/net/mock-nlb/1234567890123456/1234567890123456"
    }
  }
}


variables {
  name        = "my_web_app"
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
}

run "alb_target_group_pair_rewrites_underscores" {
  command = plan

  variables {
    container_port = 8080
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
      }
      listener_rules = [{
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
        priority     = 100
        conditions = [{
          type   = "path-pattern"
          values = ["/api/*"]
        }]
      }]
    }
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].name == "my-web-app-tg-1" && aws_lb_target_group.tg_2[0].name == "my-web-app-tg-2"
    error_message = "Underscores in var.name must be rewritten to hyphens in both ALB target group names, since ELBv2 rejects them."
  }

  assert {
    condition     = aws_ecs_service.this.name == "my_web_app"
    error_message = "The ECS service itself keeps the raw name; only ELBv2 names are rewritten."
  }
}

run "long_names_are_truncated_after_rewriting" {
  command = plan

  variables {
    name           = "my_very_long_service_name_with_underscores"
    container_port = 8080
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
      }
      listener_rules = [{
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
        priority     = 100
        conditions = [{
          type   = "path-pattern"
          values = ["/api/*"]
        }]
      }]
    }
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].name == "my-very-long-service-nam-tg-1"
    error_message = "A long name must be truncated to 24 characters with underscores rewritten before the -tg-1 suffix."
  }

  assert {
    condition     = can(regex("^[A-Za-z0-9-]+$", aws_lb_target_group.tg_1[0].name)) && length(aws_lb_target_group.tg_1[0].name) <= 32
    error_message = "Target group names must contain only alphanumerics and hyphens and fit within ELBv2's 32-character limit."
  }
}

run "nlb_target_groups_rewrite_underscores" {
  command = plan

  variables {
    name                              = "my_tcp_svc"
    deployment_type                   = "rolling"
    container_port                    = 5000
    load_balancer_security_group_id   = "sg-12345678"
    load_balancer_ingress_cidr_blocks = ["0.0.0.0/0"]
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listeners = [
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5000
          protocol        = "TCP"
          container_port  = 5000
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5443
          protocol        = "TLS"
          container_port  = 5443
          target_protocol = "TLS"
          certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        },
      ]
    }
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].name == "my-tcp-svc-tg-1" && aws_lb_target_group.nlb_additional["5443"].name == "my-tcp-svc-5443-tg"
    error_message = "Both the primary and per-listener NLB target group names must have underscores rewritten to hyphens."
  }
}
