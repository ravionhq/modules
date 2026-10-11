# Preview ingress module tests. Run from the module root: tofu test
#
# Every run is a plan against mocked providers: nothing is created.

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-2"
    }
  }

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
        { association_id = "vpc-cidr-assoc-2", cidr_block = "10.1.0.0/16", state = "associated" },
        { association_id = "vpc-cidr-assoc-3", cidr_block = "10.9.0.0/16", state = "disassociated" },
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
      arn      = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/previews/1234567890123456"
      dns_name = "previews-1234567890123456.elb.us-east-2.amazonaws.com"
      zone_id  = "ZLMOA37VPKANP"
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
    target = aws_security_group.load_balancer
    values = {
      id = "sg-0aaaaaaaaaaaaaaaa"
    }
  }

  override_resource {
    target = aws_security_group.router
    values = {
      id = "sg-0bbbbbbbbbbbbbbbb"
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
      id          = "cert_test"
      arn         = "arn:aws:acm:us-east-2:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      domain_name = "previews.example-apex.test"
      status      = "ISSUED"
    }
  }
}

variables {
  name                  = "previews"
  module_instance_id    = "minst_test"
  ravion_aws_account_id = "aws_testaccount"
  domain_name           = "previews"
  region                = "us-east-2"
  vpc_id                = "vpc-12345678"
  public_subnet_ids     = ["subnet-0a", "subnet-0b"]
  router_subnet_ids     = ["subnet-1a", "subnet-1b"]
}

run "load_balancer_terminates_tls_with_the_wildcard_certificate" {
  command = plan

  assert {
    condition     = aws_lb.this.load_balancer_type == "network" && aws_lb.this.internal == false && aws_lb.this.enable_cross_zone_load_balancing == true
    error_message = "The entry point must be an internet-facing Network Load Balancer with cross-zone load balancing"
  }

  assert {
    condition     = aws_lb.this.subnets == toset(["subnet-0a", "subnet-0b"]) && aws_lb.this.security_groups == toset(["sg-0aaaaaaaaaaaaaaaa"])
    error_message = "The load balancer must sit in the public subnets behind its own security group"
  }

  assert {
    condition     = aws_lb_listener.tls.port == 443 && aws_lb_listener.tls.protocol == "TLS" && aws_lb_listener.tls.certificate_arn == ravion_aws_acm_certificate.this.arn
    error_message = "The TLS listener on 443 must serve the wildcard certificate as its default certificate"
  }

  assert {
    condition     = aws_lb_listener.tls.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.tls.alpn_policy == null
    error_message = "The TLS listener must use a TLS 1.2+ policy and must not negotiate HTTP/2, which the router is not handed over plain TCP"
  }

  assert {
    condition     = aws_lb_listener.tls.default_action[0].type == "forward" && aws_lb_listener.tls.default_action[0].target_group_arn == aws_lb_target_group.traffic.arn
    error_message = "The TLS listener must forward to the router's traffic port"
  }

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "TCP" && aws_lb_listener.http.default_action[0].target_group_arn == aws_lb_target_group.redirect.arn
    error_message = "The TCP listener on 80 must forward to the router's redirect port"
  }
}

run "target_groups_reach_the_router_ports" {
  command = plan

  assert {
    condition     = aws_lb_target_group.traffic.port == 8080 && aws_lb_target_group.traffic.protocol == "TCP" && aws_lb_target_group.traffic.target_type == "instance"
    error_message = "Decrypted traffic must reach the router instance on TCP 8080"
  }

  assert {
    condition     = aws_lb_target_group.redirect.port == 8081 && aws_lb_target_group.redirect.protocol == "TCP" && aws_lb_target_group.redirect.target_type == "instance"
    error_message = "Plain HTTP must reach the router instance on TCP 8081"
  }

  assert {
    condition = alltrue([
      for target_group in [aws_lb_target_group.traffic, aws_lb_target_group.redirect] :
      target_group.health_check[0].protocol == "HTTP" && target_group.health_check[0].port == "8082" && target_group.health_check[0].path == "/healthz" && target_group.health_check[0].matcher == "200"
    ])
    error_message = "Both target groups must health check the router over HTTP on /healthz, port 8082"
  }

  assert {
    condition     = aws_lb_target_group.traffic.preserve_client_ip == "true" && aws_lb_target_group.redirect.preserve_client_ip == "true"
    error_message = "The router must see the client's address"
  }

  assert {
    condition     = aws_lb_target_group.traffic.name == "previews-https" && aws_lb_target_group.redirect.name == "previews-http"
    error_message = "Short names must be kept readable in the target group names"
  }
}

run "long_names_fit_the_target_group_name_limit" {
  command = plan

  variables {
    name = "a-thirty-two-character-name-0001"
  }

  assert {
    condition     = length(aws_lb_target_group.traffic.name) <= 32 && length(aws_lb_target_group.redirect.name) <= 32
    error_message = "Target group names must fit in 32 characters"
  }

  assert {
    condition     = aws_lb_target_group.traffic.name != aws_lb_target_group.redirect.name && endswith(aws_lb_target_group.traffic.name, "-https") && endswith(aws_lb_target_group.redirect.name, "-http")
    error_message = "A shortened name must still tell the two target groups apart"
  }
}

run "wildcard_certificate_points_at_the_load_balancer" {
  command = plan

  assert {
    condition     = ravion_aws_acm_certificate.this.wildcard == true && ravion_aws_acm_certificate.this.name == "previews"
    error_message = "The module must issue one wildcard certificate under the domain name leaf"
  }

  assert {
    condition     = ravion_aws_acm_certificate.this.module_instance_id == "minst_test" && ravion_aws_acm_certificate.this.aws_account_id == "aws_testaccount" && ravion_aws_acm_certificate.this.aws_region == "us-east-2"
    error_message = "The certificate must carry the module instance, account and region"
  }

  assert {
    condition     = ravion_aws_acm_certificate.this.target_dns_name == aws_lb.this.dns_name && ravion_aws_acm_certificate.this.target_zone_id == aws_lb.this.zone_id
    error_message = "The wildcard record must point at the load balancer"
  }
}

run "load_balancer_security_group_admits_the_listeners_only" {
  command = plan

  variables {
    ingress_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.load_balancer) == 4
    error_message = "Each allowed CIDR must get exactly one rule per listener"
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.load_balancer :
      rule.security_group_id == "sg-0aaaaaaaaaaaaaaaa" && rule.ip_protocol == "tcp" && rule.from_port == rule.to_port && contains([80, 443], rule.from_port) && contains(["203.0.113.0/24", "198.51.100.0/24"], rule.cidr_ipv4)
    ])
    error_message = "The load balancer must accept only TCP 443 and 80 from the allowed CIDRs"
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.load_balancer) == 3
    error_message = "The load balancer must have one egress rule per router port"
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_egress_rule.load_balancer :
      rule.security_group_id == "sg-0aaaaaaaaaaaaaaaa" && rule.referenced_security_group_id == "sg-0bbbbbbbbbbbbbbbb" && rule.cidr_ipv4 == null && rule.ip_protocol == "tcp" && rule.from_port == rule.to_port && contains([8080, 8081, 8082], rule.from_port)
    ])
    error_message = "The load balancer must reach only the router's three ports"
  }
}

run "empty_ingress_list_closes_the_load_balancer" {
  command = plan

  variables {
    ingress_cidr_blocks = []
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.load_balancer) == 0
    error_message = "An empty CIDR list must create no ingress rules"
  }
}

run "router_accepts_traffic_from_the_load_balancer_only" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.router) == 3
    error_message = "The router must have exactly one ingress rule per port it listens on"
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.router :
      rule.security_group_id == "sg-0bbbbbbbbbbbbbbbb" && rule.referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa" && rule.cidr_ipv4 == null && rule.cidr_ipv6 == null && rule.prefix_list_id == null
    ])
    error_message = "Every router ingress rule must name the load balancer's security group as its only source"
  }

  assert {
    condition     = toset([for rule in aws_vpc_security_group_ingress_rule.router : rule.from_port]) == toset([8080, 8081, 8082]) && alltrue([for rule in aws_vpc_security_group_ingress_rule.router : rule.from_port == rule.to_port && rule.ip_protocol == "tcp"])
    error_message = "The router must accept TCP 8080, 8081 and 8082 and nothing else"
  }
}

run "router_reaches_the_control_plane_and_the_preview_port_range_only" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.router_https) == 1 && aws_vpc_security_group_egress_rule.router_https["443"].from_port == 443 && aws_vpc_security_group_egress_rule.router_https["443"].to_port == 443 && aws_vpc_security_group_egress_rule.router_https["443"].ip_protocol == "tcp" && aws_vpc_security_group_egress_rule.router_https["443"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "The router's only route out of the VPC must be HTTPS"
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.router_previews)) == toset(["10.0.0.0/16", "10.1.0.0/16"])
    error_message = "The preview port range must be opened to every associated VPC CIDR and to no other address"
  }

  assert {
    condition = alltrue([
      for cidr, rule in aws_vpc_security_group_egress_rule.router_previews :
      rule.security_group_id == "sg-0bbbbbbbbbbbbbbbb" && rule.cidr_ipv4 == cidr && rule.ip_protocol == "tcp" && rule.from_port == 20000 && rule.to_port == 20998
    ])
    error_message = "Inside the VPC the router must reach TCP 20000-20998 only"
  }
}

run "control_plane_on_another_port_gets_its_own_egress_rule" {
  command = plan

  variables {
    ravion_api_url = "https://control.example.test:8443"
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.router_https)) == toset(["443", "8443"])
    error_message = "A control plane on another port must be reachable, beside 443 for release downloads"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.router_https["8443"].from_port == 8443 && aws_vpc_security_group_egress_rule.router_https["8443"].to_port == 8443
    error_message = "The extra rule must open the control plane's port only"
  }
}

run "one_router_instance_is_tagged_for_enrollment" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.router.min_size == 1 && aws_autoscaling_group.router.max_size == 1 && aws_autoscaling_group.router.desired_capacity == 1
    error_message = "The group must keep exactly one router instance"
  }

  assert {
    condition     = aws_autoscaling_group.router.target_group_arns == toset([aws_lb_target_group.traffic.arn, aws_lb_target_group.redirect.arn])
    error_message = "The instance must be registered with both target groups"
  }

  assert {
    condition     = one([for tag in aws_autoscaling_group.router.tag : tag if tag.key == "ravion:preview-router"]).value == "minst_test" && one([for tag in aws_autoscaling_group.router.tag : tag if tag.key == "ravion:preview-router"]).propagate_at_launch == true
    error_message = "The group must propagate the ravion:preview-router tag with the module instance id"
  }

  assert {
    condition     = one([for spec in aws_launch_template.router.tag_specifications : spec if spec.resource_type == "instance"]).tags["ravion:preview-router"] == "minst_test"
    error_message = "The instance must carry the ravion:preview-router tag from the moment it launches"
  }

  assert {
    condition     = aws_autoscaling_group.router.vpc_zone_identifier == toset(["subnet-1a", "subnet-1b"])
    error_message = "The router must launch in the router subnets"
  }

  assert {
    condition     = aws_autoscaling_group.router.health_check_type == "ELB" && aws_autoscaling_group.router.wait_for_elb_capacity == 1
    error_message = "A router that never turns healthy behind the load balancer must be replaced, and must fail the apply that launched it"
  }

  assert {
    condition     = aws_autoscaling_group.router.instance_refresh[0].strategy == "Rolling"
    error_message = "A changed launch template must replace the running router"
  }
}

run "launch_template_is_locked_down" {
  command = plan

  assert {
    condition     = aws_launch_template.router.metadata_options[0].http_tokens == "required" && aws_launch_template.router.metadata_options[0].http_endpoint == "enabled" && aws_launch_template.router.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The instance must require IMDSv2"
  }

  assert {
    condition     = aws_launch_template.router.network_interfaces[0].security_groups == toset(["sg-0bbbbbbbbbbbbbbbb"]) && aws_launch_template.router.network_interfaces[0].associate_public_ip_address == "false"
    error_message = "The instance must use the router security group alone and no public address by default"
  }

  assert {
    condition     = aws_launch_template.router.block_device_mappings[0].device_name == "/dev/xvda" && aws_launch_template.router.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "The root volume must be encrypted"
  }

  assert {
    condition     = aws_launch_template.router.image_id == "ami-0aaaaaaaaaaaaaaaa" && aws_launch_template.router.instance_type == "t3.small"
    error_message = "The instance must default to a t3.small from the looked-up image"
  }
}

run "user_data_installs_and_starts_the_router" {
  command = plan

  assert {
    condition     = startswith(base64decode(aws_launch_template.router.user_data), "#!/bin/bash\n") && strcontains(base64decode(aws_launch_template.router.user_data), "\nset -Eeuo pipefail\n")
    error_message = "The boot script must stop at the first failing step"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "RAVION_API_URL=https://api.ravion.com\n") && strcontains(base64decode(aws_launch_template.router.user_data), "RAVION_PREVIEW_ROUTER_MODULE_INSTANCE_ID=minst_test\n")
    error_message = "The boot script must hand the router its control plane and its module instance id"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "https://api.ravion.com/sandbox-host/v1/releases/current?platform=linux-amd64")
    error_message = "The boot script must download the current runner release for the image's platform from the control plane"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "file=binary") && strcontains(base64decode(aws_launch_template.router.user_data), "file=checksum") && strcontains(base64decode(aws_launch_template.router.user_data), "sha256sum --check")
    error_message = "The boot script must verify the download against the release's checksum"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "ExecStart=/usr/local/bin/runner preview-router --listen :8080 --listen-redirect :8081 --listen-health :8082\n")
    error_message = "The unit must start the router on the ports the load balancer targets"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "systemctl enable --now ravion-preview-router.service")
    error_message = "The boot script must enable and start the router unit"
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.router.user_data), "set -x") && !strcontains(base64decode(aws_launch_template.router.user_data), "curl -v")
    error_message = "The boot script must not trace commands or log the signed download URLs"
  }
}

run "overrides_reach_the_instance" {
  command = plan

  variables {
    ravion_api_url           = "https://api.staging.example.test"
    instance_type            = "m7i.large"
    image_id                 = "ami-0123456789abcdef0"
    router_public_ip_enabled = true
  }

  override_data {
    target = data.aws_ami.router
    values = {
      id               = "ami-0123456789abcdef0"
      architecture     = "x86_64"
      root_device_name = "/dev/sda1"
    }
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "RAVION_API_URL=https://api.staging.example.test\n") && strcontains(base64decode(aws_launch_template.router.user_data), "https://api.staging.example.test/sandbox-host/v1/releases/current?platform=linux-amd64")
    error_message = "A control plane override must reach both the router's environment and the release download"
  }

  assert {
    condition     = aws_launch_template.router.image_id == "ami-0123456789abcdef0" && aws_launch_template.router.instance_type == "m7i.large" && aws_launch_template.router.block_device_mappings[0].device_name == "/dev/sda1"
    error_message = "An explicit image and instance type must be used as given"
  }

  assert {
    condition     = aws_launch_template.router.network_interfaces[0].associate_public_ip_address == "true"
    error_message = "A router in public subnets must be given a public address"
  }
}

run "arm_image_downloads_the_arm_release" {
  command = plan

  variables {
    instance_type = "t4g.small"
  }

  override_data {
    target = data.aws_ec2_instance_type.router
    values = {
      supported_architectures = ["arm64"]
    }
  }

  override_data {
    target = data.aws_ami.router
    values = {
      id               = "ami-0cccccccccccccccc"
      architecture     = "arm64"
      root_device_name = "/dev/xvda"
    }
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.router.user_data), "/sandbox-host/v1/releases/current?platform=linux-arm64")
    error_message = "The release platform must follow the image's architecture"
  }
}

run "image_and_instance_type_must_share_an_architecture" {
  command = plan

  variables {
    instance_type = "t4g.small"
    image_id      = "ami-0123456789abcdef0"
  }

  override_data {
    target = data.aws_ec2_instance_type.router
    values = {
      supported_architectures = ["arm64"]
    }
  }

  expect_failures = [aws_launch_template.router]
}

run "session_manager_access_is_the_instance_role_only_permission" {
  command = plan

  assert {
    condition     = length(aws_iam_role.router) == 1 && length(aws_iam_instance_profile.router) == 1 && length(aws_iam_role_policy_attachment.router_ssm) == 1
    error_message = "Session Manager access must be on by default"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.router_ssm[0].policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The instance role must hold the Session Manager core policy and nothing else"
  }

  assert {
    condition     = aws_launch_template.router.iam_instance_profile[0].arn == aws_iam_instance_profile.router[0].arn
    error_message = "The instance must use the module's instance profile"
  }
}

run "session_manager_off_leaves_the_instance_without_a_role" {
  command = plan

  variables {
    ssm_enabled = false
  }

  assert {
    condition     = length(aws_iam_role.router) == 0 && length(aws_iam_instance_profile.router) == 0 && length(aws_iam_role_policy_attachment.router_ssm) == 0
    error_message = "Turning Session Manager off must create no role or instance profile"
  }

  assert {
    condition     = length(aws_launch_template.router.iam_instance_profile) == 0
    error_message = "The instance must launch with no instance profile"
  }
}

run "outputs_describe_the_router" {
  command = plan

  assert {
    condition     = output.sandbox_router_id == "minst_test"
    error_message = "sandbox_router_id must be the module instance id"
  }

  assert {
    condition     = output.sandbox_router_dns_name == "previews-1234567890123456.elb.us-east-2.amazonaws.com" && output.sandbox_router_zone_id == "ZLMOA37VPKANP"
    error_message = "The router's DNS name and zone must be the load balancer's"
  }

  assert {
    condition     = output.sandbox_router_load_balancer_arn == "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/previews/1234567890123456"
    error_message = "sandbox_router_load_balancer_arn must be the load balancer's ARN"
  }

  assert {
    condition     = output.sandbox_router_security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "sandbox_router_security_group_id must be the router instance's security group, not the load balancer's"
  }

  assert {
    condition     = output.wildcard_domain_name == "previews.example-apex.test"
    error_message = "wildcard_domain_name must be the certificate's apex"
  }

  assert {
    condition     = output.aws_account_id == "123456789012" && output.region == "us-east-2"
    error_message = "The account and region outputs must describe where the resources live"
  }
}
