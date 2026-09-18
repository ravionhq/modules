################################################################################
# Target group name
#
# ELBv2 accepts only alphanumerics and hyphens in target group names, while
# var.name also permits underscores because the same name seeds the ECR
# repository. The name the target group receives must therefore never carry
# an underscore, whether it is short enough to keep whole or long enough to be
# truncated and hashed.
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
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/1234567890abcdef"
    }
  }
}

variables {
  name                       = "test-workload"
  region                     = "us-east-1"
  vpc_id                     = "vpc-0123456789abcdef0"
  kubernetes_service_enabled = true
  release_name               = "test-workload"
  release_namespace          = "test"
  listener_arn               = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/1234567890abcdef/1234567890abcdef"
}

run "short_name_keeps_its_full_form" {
  command = plan

  assert {
    condition     = output.target_group_name == "test-workload-tg"
    error_message = "A short hyphenated name must be used as-is with the -tg suffix."
  }
}

run "underscores_become_hyphens_in_a_short_name" {
  command = plan

  variables {
    name = "my_web_app"
  }

  assert {
    condition     = output.target_group_name == "my-web-app-tg"
    error_message = "Underscores in var.name must be rewritten to hyphens, since ELBv2 rejects them in target group names."
  }
}

run "underscores_become_hyphens_in_a_truncated_name" {
  command = plan

  variables {
    name = "my_very_long_workload_name_with_underscores"
  }

  assert {
    condition     = startswith(output.target_group_name, "my-very-long-workloa-") && endswith(output.target_group_name, "-tg")
    error_message = "A long name must be truncated to its first 20 characters, with underscores rewritten, then carry the hash and -tg suffix."
  }

  assert {
    condition     = can(regex("^[A-Za-z0-9-]+$", output.target_group_name)) && length(output.target_group_name) <= 32
    error_message = "The target group name must contain only alphanumerics and hyphens and fit within ELBv2's 32-character limit."
  }
}

run "hash_is_keyed_on_the_raw_name" {
  command = plan

  variables {
    name = "my_very_long_workload_name_with_underscores"
  }

  assert {
    condition     = output.target_group_name == "my-very-long-workloa-${substr(sha1("my_very_long_workload_name_with_underscores"), 0, 8)}-tg"
    error_message = "The collision hash must be computed from the raw name so it stays stable."
  }
}

run "an_explicit_name_replaces_the_derived_one" {
  command = plan

  variables {
    name              = "my_web_app"
    target_group_name = "my-web-app-eks-tg"
  }

  assert {
    condition     = output.target_group_name == "my-web-app-eks-tg"
    error_message = "An explicit target_group_name must be used verbatim, for a workload whose derived name another target group already owns."
  }
}
