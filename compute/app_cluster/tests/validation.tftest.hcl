# App Cluster variable validation tests. Run from the module root: tofu test
#
# Ids and origins are refused unless they are exactly an id or an origin. A
# custom domain is a wildcard, because every app gets its own hostname under
# it, and short enough for every app hostname below it to be a domain name.

mock_provider "aws" {
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_vpc.this
    values = {
      cidr_block              = "10.0.0.0/16"
      cidr_block_associations = []
    }
  }

  override_resource {
    target = aws_lb.this
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/apps/1234567890123456"
    }
  }

  override_resource {
    target = aws_lb_target_group.traffic
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-https/1111111111111111"
    }
  }

  override_resource {
    target = aws_lb_target_group.redirect
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-http/2222222222222222"
    }
  }
}

mock_provider "ravion" {
  override_resource {
    target = ravion_aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-2:123456789012:certificate/99999999-9999-9999-9999-999999999999"
    }
  }
}

variables {
  name               = "apps"
  module_instance_id = "minst_test"
  ravion_domain_name = "apps"
  ravion_api_url     = "https://api.example.test"
  vpc_id             = "vpc-12345678"
  public_subnet_ids  = ["subnet-0a", "subnet-0b"]
  router_subnet_ids  = ["subnet-1a", "subnet-1b"]
}

run "plain_http_control_plane_is_refused" {
  command = plan

  variables {
    ravion_api_url = "http://api.example.test"
  }

  expect_failures = [var.ravion_api_url]
}

run "control_plane_url_with_a_path_is_refused" {
  command = plan

  variables {
    ravion_api_url = "https://api.example.test/v1"
  }

  expect_failures = [var.ravion_api_url]
}

run "module_instance_id_must_be_an_id" {
  command = plan

  variables {
    module_instance_id = "minst_test; reboot"
  }

  expect_failures = [var.module_instance_id]
}

run "ravion_domain_name_must_be_one_dns_label" {
  command = plan

  variables {
    ravion_domain_name = "apps.example.com"
  }

  expect_failures = [var.ravion_domain_name]
}

run "custom_domain_must_be_a_wildcard" {
  command = plan

  variables {
    domains = ["apps.example.com"]
  }

  expect_failures = [var.domains]
}

run "custom_domain_wildcard_must_be_the_first_label_alone" {
  command = plan

  variables {
    domains = ["*.apps.*.example.com"]
  }

  expect_failures = [var.domains]
}

run "custom_domain_wildcard_needs_a_domain_below_it" {
  command = plan

  variables {
    domains = ["*.com"]
  }

  expect_failures = [var.domains]
}

run "at_most_ten_custom_domains" {
  command = plan

  variables {
    domains = [for index in range(11) : "*.apps-${index}.example.com"]
  }

  expect_failures = [var.domains]
}

# The longest app hostname, <app>-<exposure>.<domain>, adds 62 characters to
# the domain, and a domain name holds 253: the domain itself, without its *.,
# may have 191.
run "custom_domain_leaves_room_for_app_hostnames" {
  command = plan

  variables {
    domains = ["*.${join(".", [for index in range(3) : join("", [for letter in range(63) : "a"])])}.com"]
  }

  expect_failures = [var.domains]
}

run "custom_domain_of_191_characters_is_accepted" {
  command = plan

  variables {
    domains = ["*.${join(".", [for index in range(2) : join("", [for letter in range(63) : "a"])])}.${join("", [for letter in range(59) : "b"])}.com"]
  }

  assert {
    condition     = length(trimprefix(one(var.domains), "*.")) == 191 && length(ravion_domain.custom) == 1
    error_message = "A custom domain of 191 characters without its *. must be accepted"
  }
}

run "name_must_fit_a_load_balancer_name" {
  command = plan

  variables {
    name = "a-name-that-is-longer-than-thirty-two-characters"
  }

  expect_failures = [var.name]
}

run "ingress_must_be_ipv4_cidrs" {
  command = plan

  variables {
    ingress_cidr_blocks = ["not-a-cidr"]
  }

  expect_failures = [var.ingress_cidr_blocks]
}

run "router_needs_a_subnet" {
  command = plan

  variables {
    router_subnet_ids = []
  }

  expect_failures = [var.router_subnet_ids]
}
