# App Cluster variable validation tests. Run from the module root: tofu test
#
# Ids and origins are refused unless they are exactly an id or an origin. A
# custom domain is a wildcard, because every app gets its own hostname under
# it. The sandbox pool's settings are held to the bounds Ravion's API holds
# them to, so a bad value fails the plan instead of the apply.

mock_provider "aws" {
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
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
  host_subnet_id     = "subnet-1a"
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

run "hosts_need_a_subnet" {
  command = plan

  variables {
    host_subnet_id = "default"
  }

  expect_failures = [var.host_subnet_id]
}

run "host_instance_type_must_be_an_instance_type" {
  command = plan

  variables {
    host_instance_types = [{ type = "c8id" }]
  }

  expect_failures = [var.host_instance_types]
}

run "host_instance_types_appear_once" {
  command = plan

  variables {
    host_instance_types = [{ type = "c8id.4xlarge" }, { type = "c8id.4xlarge", disk_gib = 60 }]
  }

  expect_failures = [var.host_instance_types]
}

run "host_disk_holds_the_system" {
  command = plan

  variables {
    host_instance_types = [{ type = "c8id.4xlarge", disk_gib = 20 }]
  }

  expect_failures = [var.host_instance_types]
}

run "host_disk_iops_start_at_gp3_baseline" {
  command = plan

  variables {
    host_instance_types = [{ type = "c8id.4xlarge", disk_iops = 1000 }]
  }

  expect_failures = [var.host_instance_types]
}

run "host_disk_throughput_stays_within_gp3" {
  command = plan

  variables {
    host_instance_types = [{ type = "c8id.4xlarge", disk_throughput_mbps = 2000 }]
  }

  expect_failures = [var.host_instance_types]
}

run "hosts_are_bought_on_demand" {
  command = plan

  variables {
    host_capacity_types = ["SPOT"]
  }

  expect_failures = [var.host_capacity_types]
}

run "host_markets_are_on_demand_and_spot_only" {
  command = plan

  variables {
    host_capacity_types = ["ON_DEMAND", "RESERVED"]
  }

  expect_failures = [var.host_capacity_types]
}

run "warm_hosts_policy_must_be_known" {
  command = plan

  variables {
    host_reserve_policy = { type = "ALWAYS" }
  }

  expect_failures = [var.host_reserve_policy]
}

run "warm_hosts_window_is_at_most_ninety_days" {
  command = plan

  variables {
    host_reserve_policy = { type = "PEAK", window_days = 120 }
  }

  expect_failures = [var.host_reserve_policy]
}

run "warm_hosts_count_is_not_negative" {
  command = plan

  variables {
    host_reserve_policy = { type = "FIXED", value = -1 }
  }

  expect_failures = [var.host_reserve_policy]
}

run "max_hosts_is_at_least_one" {
  command = plan

  variables {
    max_hosts = 0
  }

  expect_failures = [var.max_hosts]
}

run "max_hosts_is_at_most_one_hundred" {
  command = plan

  variables {
    max_hosts = 101
  }

  expect_failures = [var.max_hosts]
}
