################################################################################
# OpenTelemetry
#
# The deploy sets the OTEL_* environment variables; the stack only refuses a
# workload that turns OpenTelemetry on against add-ons that do not receive OTLP.
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
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_lb_listener" {
    defaults = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1234567890abcdef"
      protocol          = "HTTPS"
      port              = 443
    }
  }
  mock_data "aws_lb" {
    defaults = {
      dns_name = "test.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
      subnets  = ["subnet-0a", "subnet-0b"]
    }
  }
  mock_data "aws_subnet" {
    defaults = {
      cidr_block = "10.0.0.0/20"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/1234567890abcdef"
    }
  }
}

variables {
  name         = "test-workload"
  region       = "us-east-1"
  vpc_id       = "vpc-0123456789abcdef0"
  listener_arn = null
}

run "otel_off_needs_no_endpoint" {
  command = plan
}

run "otel_on_with_the_add_ons_endpoint" {
  command = plan

  variables {
    otel_enabled            = true
    otel_collector_endpoint = "http://ravion-otel-collector.ravion-operator.svc.cluster.local:4318"
  }
}

run "otel_on_without_an_endpoint_is_refused" {
  command = plan

  variables {
    otel_enabled            = true
    otel_collector_endpoint = null
  }

  expect_failures = [var.otel_collector_endpoint]
}

run "otel_on_with_a_blank_endpoint_is_refused" {
  command = plan

  variables {
    otel_enabled            = true
    otel_collector_endpoint = ""
  }

  expect_failures = [var.otel_collector_endpoint]
}
