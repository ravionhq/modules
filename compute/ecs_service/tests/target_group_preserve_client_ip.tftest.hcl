################################################################################
# Client IP preservation
#
# preserve_client_ip is only configurable on NLB TCP and TLS target groups, so
# the module passes var.load_balancer_attachment.target_group.preserve_client_ip
# to those groups and leaves it unset for ALB and UDP target groups.
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

# The module declares the ravion provider, so Terraform configures it even when
# no ravion resource is planned; an empty mock keeps its real Configure (which
# requires RAVION_API_KEY) from failing the plan.
mock_provider "ravion" {}

variables {
  name        = "my_web_app"
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
}

run "nlb_tcp_and_tls_target_groups_preserve_client_ip" {
  command = plan

  variables {
    name                              = "my-tcp-svc"
    deployment_type                   = "rolling"
    container_port                    = 5000
    load_balancer_security_group_id   = "sg-12345678"
    load_balancer_ingress_cidr_blocks = ["0.0.0.0/0"]
    load_balancer_attachment = {
      target_group = {
        port               = 5000
        protocol           = "TCP"
        preserve_client_ip = true
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
    condition     = aws_lb_target_group.tg_1[0].preserve_client_ip == "true" && aws_lb_target_group.nlb_additional["5443"].preserve_client_ip == "true"
    error_message = "NLB TCP and TLS target groups must preserve client IPs when enabled."
  }
}

run "nlb_target_group_preserve_client_ip_disabled" {
  command = plan

  variables {
    name                              = "my-tcp-svc"
    deployment_type                   = "rolling"
    container_port                    = 5000
    load_balancer_security_group_id   = "sg-12345678"
    load_balancer_ingress_cidr_blocks = ["0.0.0.0/0"]
    load_balancer_attachment = {
      target_group = {
        port               = 5000
        protocol           = "TCP"
        preserve_client_ip = false
      }
      nlb_listeners = [
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5000
          protocol        = "TCP"
          container_port  = 5000
          target_protocol = "TCP"
        },
      ]
    }
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].preserve_client_ip == "false"
    error_message = "NLB TCP target groups must not preserve client IPs when disabled."
  }
}
