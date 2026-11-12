# Managed-domain routing tests for EKS services.

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
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock-alb/1234567890123456"
      protocol          = "HTTPS"
      port              = 443
    }
  }

  mock_data "aws_lb" {
    defaults = {
      dns_name = "mock-alb-1234567890.us-east-1.elb.amazonaws.com"
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
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock-tg/1234567890123456"
      arn_suffix = "targetgroup/mock-tg/1234567890123456"
    }
  }

  mock_resource "aws_lb_listener_rule" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/mock-alb/1234567890123456/1234567890123456/1234567890123456"
    }
  }
}

mock_provider "ravion" {
  mock_resource "ravion_domain" {
    defaults = {
      id          = "domain_test"
      domain_name = "test-service.cluster.ravion.app"
      url         = "https://test-service.cluster.ravion.app"
    }
  }

  mock_resource "ravion_aws_acm_certificate" {
    defaults = {
      id          = "cert_test"
      arn         = "arn:aws:acm:us-east-1:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      domain_name = "www.example.com"
      status      = "ISSUED"
    }
  }
}

variables {
  name                       = "test-service"
  region                     = "us-east-1"
  module_instance_id         = "minst_test"
  module_instance_given_id   = "test-service"
  vpc_id                     = "vpc-12345678"
  listener_arn               = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock-alb/1234567890123456/1234567890123456"
  cluster_parent_fqdn        = "cluster.ravion.app"
  cluster_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock-alb/1234567890123456/1234567890123456"
  cluster_alb_dns_name       = "mock-alb-1234567890.us-east-1.elb.amazonaws.com"
  cluster_alb_zone_id        = "Z35SXDOTRQ7X7K"
}

run "empty_domains_creates_auto_domain_and_listener_rule" {
  command = plan

  assert {
    condition     = length(ravion_domain.wildcard) == 1
    error_message = "An empty domains list must create the service auto-domain under the cluster apex"
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.svc) == 0
    error_message = "The auto-domain must ride the cluster wildcard without a service certificate"
  }

  assert {
    condition     = length(aws_lb_listener_rule.ravion) == 1
    error_message = "Managed mode must create a host-header listener rule"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 0
    error_message = "Managed mode must suppress the caller-provided listener rule"
  }
}

run "custom_domain_creates_certificate_domain_and_rule" {
  command = plan

  variables {
    domains               = ["www.example.com"]
    ravion_domain_name    = "fallback"
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.svc) == 1
    error_message = "A custom domain must create one service certificate"
  }

  assert {
    condition     = length(ravion_domain.custom) == 1
    error_message = "A custom domain must create one routed domain allocation"
  }

  assert {
    condition     = length(ravion_domain.wildcard) == 1
    error_message = "The default Ravion domain must be served alongside the custom domain"
  }

  assert {
    condition     = length(aws_lb_listener_rule.ravion) == 1
    error_message = "The custom hostname must be routed to the service target group"
  }

  assert {
    condition = (
      length(local.ravion_host_headers) == 2
      && local.ravion_host_headers[0] == "www.example.com"
      && local.ravion_host_headers[1] == "fallback.cluster.ravion.app"
    )
    error_message = "The custom domain and then the default Ravion domain must be routed"
  }

  assert {
    condition = (
      output.ravion_domain_fqdn == "www.example.com"
      && output.ravion_domain_url == "https://www.example.com"
      && output.ravion_domain_fqdns == tolist(["www.example.com", "fallback.cluster.ravion.app"])
    )
    error_message = "The first configured custom domain must be the primary output"
  }
}

run "mixed_domains_share_one_custom_certificate" {
  command = plan

  variables {
    domains = [
      " api.cluster.ravion.app. ",
      "WWW.example.com",
      "www.example.com.",
      "api.example.com",
    ]
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition = (
      length(local.effective_domains) == 4
      && local.effective_domains[0] == "api.cluster.ravion.app"
      && local.effective_domains[1] == "www.example.com"
      && local.effective_domains[2] == "api.example.com"
      && local.effective_domains[3] == "test-service.cluster.ravion.app"
    )
    error_message = "Explicit domains must be normalized and deduplicated in order, followed by the default Ravion domain"
  }

  assert {
    condition     = length(ravion_domain.wildcard) == 2
    error_message = "The explicit wildcard domain and the default Ravion domain must both be allocated"
  }

  assert {
    condition     = length(ravion_domain.custom) == 2
    error_message = "External domains must receive routed domain allocations"
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.svc) == 1
    error_message = "All custom domains for a service must share one certificate"
  }

  assert {
    condition = (
      output.ravion_domain_fqdn == "api.cluster.ravion.app"
      && output.ravion_domain_fqdns == tolist([
        "api.cluster.ravion.app",
        "www.example.com",
        "api.example.com",
        "test-service.cluster.ravion.app",
      ])
    )
    error_message = "The first explicit domain must remain the primary output"
  }
}

run "ravion_domain_name_names_the_default_domain" {
  command = plan

  variables {
    ravion_domain_name    = "api"
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition = (
      length(local.effective_domains) == 1
      && local.effective_domains[0] == "api.cluster.ravion.app"
      && output.ravion_domain_fqdn == "api.cluster.ravion.app"
      && output.ravion_domain_fqdns == tolist(["api.cluster.ravion.app"])
    )
    error_message = "ravion_domain_name must name the default Ravion domain"
  }

  assert {
    condition     = length(ravion_domain.wildcard) == 1 && length(ravion_domain.custom) == 0
    error_message = "The default Ravion domain must ride the cluster wildcard"
  }
}

run "default_domain_off_serves_only_custom_domains" {
  command = plan

  variables {
    ravion_domain_enabled = false
    domains               = ["www.example.com"]
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition     = length(ravion_domain.wildcard) == 0 && length(local.ravion_host_headers) == 1 && local.ravion_host_headers[0] == "www.example.com"
    error_message = "Turning the default Ravion domain off must serve only the custom domains"
  }
}

run "default_domain_off_without_custom_domains_is_rejected" {
  command = plan

  variables {
    ravion_domain_enabled = false
    domains               = [" "]
  }

  expect_failures = [var.ravion_domain_enabled]
}

run "default_domain_listed_as_custom_is_served_once" {
  command = plan

  variables {
    domains               = ["test-service.cluster.ravion.app", "www.example.com"]
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition = (
      length(local.effective_domains) == 2
      && local.effective_domains[0] == "test-service.cluster.ravion.app"
      && local.effective_domains[1] == "www.example.com"
      && length(ravion_domain.wildcard) == 1
    )
    error_message = "A default Ravion domain also listed as a custom domain must be served once, in its listed position"
  }
}

run "normalized_blank_domains_use_ravion_fallback" {
  command = plan

  variables {
    ravion_domain_name = "fallback"
    domains            = ["   ", ".", " . "]
  }

  assert {
    condition = (
      length(local.normalized_domains) == 0
      && length(local.effective_domains) == 1
      && local.effective_domains[0] == "fallback.cluster.ravion.app"
    )
    error_message = "Domains that normalize to empty must still use the configured fallback"
  }
}

run "manual_mode_has_no_managed_domains" {
  command = plan

  variables {
    cluster_parent_fqdn = null
    domains             = ["api.example.com"]
  }

  assert {
    condition     = length(ravion_domain.wildcard) == 0 && length(ravion_domain.custom) == 0 && length(aws_lb_listener_rule.ravion) == 0 && output.ravion_domain_fqdn == null && length(output.ravion_domain_fqdns) == 0
    error_message = "Manual mode must not allocate managed domains or rules"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "Manual mode must keep the caller-provided listener rule"
  }
}

run "deep_name_under_managed_apex_is_rejected" {
  command = plan

  variables {
    domains               = ["deep.api.cluster.ravion.app"]
    ravion_aws_account_id = "aws_testaccount"
  }

  expect_failures = [ravion_aws_acm_certificate.svc]
}

run "six_hosts_make_two_listener_rule_chunks" {
  command = plan

  variables {
    domains = [
      "a.example.com",
      "b.example.com",
      "c.example.com",
      "d.example.com",
      "e.example.com",
    ]
    ravion_aws_account_id = "aws_testaccount"
  }

  assert {
    condition     = length(local.ravion_host_headers) == 6 && length(aws_lb_listener_rule.ravion) == 2
    error_message = "Six host headers must be split into two listener rules of at most five"
  }
}

run "worker_without_listener_creates_nothing_new" {
  command = plan

  variables {
    listener_arn               = null
    cluster_parent_fqdn        = null
    cluster_https_listener_arn = null
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 0 && length(aws_lb_listener_rule.ravion) == 0 && length(ravion_domain.wildcard) == 0 && length(ravion_domain.custom) == 0 && length(ravion_aws_acm_certificate.svc) == 0
    error_message = "A workload without a listener must create no routing or domain resources"
  }
}
