# App Cluster module tests. Run from the module root: tofu test
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

  override_resource {
    target = aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/apps/1234567890123456"
      arn_suffix = "net/apps/1234567890123456"
      dns_name   = "apps-1234567890123456.elb.us-east-2.amazonaws.com"
      zone_id    = "ZLMOA37VPKANP"
    }
  }

  override_resource {
    target = aws_lb_target_group.traffic
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-https/1111111111111111"
      arn_suffix = "targetgroup/apps-https/1111111111111111"
    }
  }

  override_resource {
    target = aws_lb_target_group.redirect
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-http/2222222222222222"
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
    target = aws_security_group.sandbox_hosts
    values = {
      id = "sg-0cccccccccccccccc"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.router
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/apps-router"
    }
  }
}

mock_provider "ravion" {
  override_resource {
    target = ravion_aws_acm_certificate.this
    values = {
      id          = "cert_test"
      arn         = "arn:aws:acm:us-east-2:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      domain_name = "apps.example-apex.test"
      status      = "ISSUED"
    }
  }

  override_resource {
    target = ravion_sandbox_pool.this
    values = {
      id = "ee_test"
    }
  }
}

variables {
  name                  = "apps"
  module_instance_id    = "minst_test"
  ravion_aws_account_id = "aws_testaccount"
  ravion_domain_name    = "apps"
  ravion_api_url        = "https://api.example.test"
  region                = "us-east-2"
  vpc_id                = "vpc-12345678"
  public_subnet_ids     = ["subnet-0a", "subnet-0b"]
  router_subnet_ids     = ["subnet-1a", "subnet-1b"]
  host_subnet_id        = "subnet-1a"
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
    condition     = aws_lb_target_group.traffic.deregistration_delay == "30" && aws_lb_target_group.redirect.deregistration_delay == "30"
    error_message = "A router Ravion replaces must be drained for the 30 seconds Ravion waits before terminating it"
  }

  assert {
    condition     = aws_lb_target_group.traffic.name == "apps-https" && aws_lb_target_group.redirect.name == "apps-http"
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
    condition     = ravion_aws_acm_certificate.this.wildcard == true && ravion_aws_acm_certificate.this.name == "apps"
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

run "wildcard_domain_defaults_to_the_module_given_id" {
  command = plan

  variables {
    ravion_domain_name       = null
    module_instance_given_id = "cluster"
  }

  assert {
    condition     = ravion_aws_acm_certificate.this.name == "cluster"
    error_message = "With no ravion_domain_name the wildcard's name leaf must be the module instance given id"
  }
}

run "no_custom_domains_adds_nothing_to_the_listener" {
  command = plan

  assert {
    condition     = length(ravion_aws_acm_certificate.custom) == 0 && length(ravion_domain.custom) == 0
    error_message = "With no custom domains the module must issue no second certificate and allocate no domain"
  }

  assert {
    condition     = length(output.custom_domain_names) == 0 && output.custom_certificate_arn == null
    error_message = "With no custom domains the custom domain outputs must be empty"
  }
}

run "custom_domains_share_one_certificate_on_the_tls_listener" {
  command = plan

  variables {
    domains = ["*.apps.example.com", "*.dev.example.org"]
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.custom) == 1 && ravion_aws_acm_certificate.custom[0].domains == toset(["*.apps.example.com", "*.dev.example.org"])
    error_message = "Every custom domain must be a name on one certificate"
  }

  assert {
    condition     = ravion_aws_acm_certificate.custom[0].target_arn == aws_lb_listener.tls.arn
    error_message = "The custom domains' certificate must be attached to the TLS listener"
  }

  assert {
    condition     = aws_lb_listener.tls.certificate_arn == ravion_aws_acm_certificate.this.arn
    error_message = "The managed wildcard certificate must stay the TLS listener's default certificate"
  }

  assert {
    condition     = output.custom_domain_names == tolist(["*.apps.example.com", "*.dev.example.org"])
    error_message = "custom_domain_names must list the custom domains as given"
  }
}

run "each_custom_domain_points_at_the_load_balancer" {
  command = plan

  variables {
    domains = ["*.apps.example.com", "*.dev.example.org"]
  }

  assert {
    condition     = toset(keys(ravion_domain.custom)) == toset(["*.apps.example.com", "*.dev.example.org"])
    error_message = "Each custom domain must get exactly one domain allocation"
  }

  assert {
    condition = alltrue([
      for domain, allocation in ravion_domain.custom :
      allocation.name == domain && allocation.module_instance_id == "minst_test" && allocation.target_dns_name == aws_lb.this.dns_name && allocation.target_zone_id == aws_lb.this.zone_id
    ])
    error_message = "Each custom domain must be allocated to this module instance and routed to the load balancer"
  }
}

run "custom_domains_are_normalized" {
  command = plan

  variables {
    domains = [" *.Apps.Example.com. ", "*.apps.example.com", ""]
  }

  assert {
    condition     = ravion_aws_acm_certificate.custom[0].domains == toset(["*.apps.example.com"]) && toset(keys(ravion_domain.custom)) == toset(["*.apps.example.com"])
    error_message = "Custom domains must be lowercased, trimmed of whitespace and a trailing dot, and listed once; blank entries must be dropped"
  }
}

run "custom_domain_under_the_ravion_apex_is_refused" {
  command = plan

  variables {
    domains = ["*.team.example-apex.test"]
  }

  expect_failures = [ravion_aws_acm_certificate.custom]
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
    condition = length(aws_vpc_security_group_egress_rule.load_balancer) == 3 && alltrue([
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

run "router_reaches_the_control_plane_and_the_app_port_range_only" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.router_https) == 1 && aws_vpc_security_group_egress_rule.router_https["443"].from_port == 443 && aws_vpc_security_group_egress_rule.router_https["443"].to_port == 443 && aws_vpc_security_group_egress_rule.router_https["443"].ip_protocol == "tcp" && aws_vpc_security_group_egress_rule.router_https["443"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "The router's only route out of the VPC must be HTTPS"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.security_group_id == "sg-0bbbbbbbbbbbbbbbb" && aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.referenced_security_group_id == "sg-0cccccccccccccccc" && aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.cidr_ipv4 == null
    error_message = "Inside the VPC the router must reach the sandbox hosts' security group only"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.ip_protocol == "tcp" && aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.from_port == 20000 && aws_vpc_security_group_egress_rule.router_to_sandbox_hosts.to_port == 20999
    error_message = "The router must reach the sandbox hosts on TCP 20000-20999, the ports hosts serve apps and their health check on"
  }
}

run "control_plane_on_another_port_gets_its_own_egress_rule" {
  command = plan

  variables {
    ravion_api_url = "https://control.example.test:8443"
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.router_https)) == toset(["443", "8443"])
    error_message = "A control plane on another port must be reachable, beside 443 for AWS APIs"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.router_https["8443"].from_port == 8443 && aws_vpc_security_group_egress_rule.router_https["8443"].to_port == 8443
    error_message = "The extra rule must open the control plane's port only"
  }
}

run "no_control_plane_url_opens_https_only" {
  command = plan

  variables {
    ravion_api_url = null
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.router_https)) == toset(["443"])
    error_message = "Without a control plane URL the router must reach port 443 alone"
  }
}

run "sandbox_hosts_admit_the_router_on_the_app_port_range_only" {
  command = plan

  assert {
    condition     = aws_security_group.sandbox_hosts.vpc_id == "vpc-12345678" && aws_security_group.sandbox_hosts.name == "apps-hosts"
    error_message = "The sandbox hosts' security group must be in the cluster's VPC"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.security_group_id == "sg-0cccccccccccccccc" && aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.referenced_security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "The sandbox hosts' rule must sit on the hosts' group and name the router's security group as its source"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.cidr_ipv6 == null && aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.prefix_list_id == null
    error_message = "No CIDR or prefix list may reach the sandbox hosts"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.from_port == 20000 && aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.to_port == 20999
    error_message = "Sandbox hosts must admit the router on TCP 20000-20999 and nothing else"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.sandbox_hosts_from_router.description == "ravion app router to sandbox hosts"
    error_message = "The router's rule on the sandbox hosts must be described as the ravion app router's"
  }
}

run "sandbox_hosts_reach_any_ipv4_address" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.sandbox_hosts.security_group_id == "sg-0cccccccccccccccc" && aws_vpc_security_group_egress_rule.sandbox_hosts.ip_protocol == "-1" && aws_vpc_security_group_egress_rule.sandbox_hosts.cidr_ipv4 == "0.0.0.0/0"
    error_message = "Sandbox hosts must reach Ravion, registries and whatever their apps call"
  }
}

run "sandbox_pool_runs_in_the_hosts_subnet_and_security_group" {
  command = plan

  assert {
    condition     = ravion_sandbox_pool.this.vpc_id == "vpc-12345678" && ravion_sandbox_pool.this.subnet_id == "subnet-1a" && ravion_sandbox_pool.this.security_group_id == "sg-0cccccccccccccccc"
    error_message = "The pool must launch its hosts in the host subnet and the sandbox hosts' security group"
  }

  assert {
    condition     = ravion_sandbox_pool.this.aws_account_id == "aws_testaccount" && ravion_sandbox_pool.this.region == "us-east-2"
    error_message = "The pool must run in the cluster's account and region"
  }
}

run "sandbox_pool_defaults_to_ravions_choice_on_demand_and_no_warm_hosts" {
  command = plan

  assert {
    condition     = length(ravion_sandbox_pool.this.instance_types) == 0
    error_message = "With no instance types the pool must let Ravion choose"
  }

  assert {
    condition     = ravion_sandbox_pool.this.capacity_types == tolist(["ON_DEMAND"])
    error_message = "The pool must buy on-demand hosts only by default"
  }

  assert {
    condition     = ravion_sandbox_pool.this.reserve_policy.type == "NONE" && ravion_sandbox_pool.this.reserve_policy.window_days == 7 && ravion_sandbox_pool.this.reserve_policy.value == 0
    error_message = "The pool must keep no warm host by default"
  }

  assert {
    condition     = ravion_sandbox_pool.this.max_hosts == 10
    error_message = "The pool must run at most 10 hosts by default"
  }
}

run "sandbox_pool_takes_its_settings_as_given" {
  command = plan

  variables {
    host_instance_types = [
      { type = "c8id.4xlarge" },
      { type = "m8i.4xlarge", disk_gib = 200, disk_iops = 6000, disk_throughput_mbps = 250 },
    ]
    host_capacity_types = ["ON_DEMAND", "SPOT"]
    host_reserve_policy = { type = "FIXED", value = 2 }
    max_hosts           = 25
  }

  assert {
    condition     = length(ravion_sandbox_pool.this.instance_types) == 2 && ravion_sandbox_pool.this.instance_types[0].type == "c8id.4xlarge" && ravion_sandbox_pool.this.instance_types[1].type == "m8i.4xlarge"
    error_message = "The pool must take the instance types in the order given"
  }

  assert {
    condition     = ravion_sandbox_pool.this.instance_types[0].disk_gib == 130 && ravion_sandbox_pool.this.instance_types[0].disk_iops == 3000 && ravion_sandbox_pool.this.instance_types[0].disk_throughput_mbps == 125
    error_message = "An instance type without disk settings must get Ravion's default root volume: 130 GiB at gp3 baseline"
  }

  assert {
    condition     = ravion_sandbox_pool.this.instance_types[1].disk_gib == 200 && ravion_sandbox_pool.this.instance_types[1].disk_iops == 6000 && ravion_sandbox_pool.this.instance_types[1].disk_throughput_mbps == 250
    error_message = "An instance type's disk settings must be used as given"
  }

  assert {
    condition     = ravion_sandbox_pool.this.capacity_types == tolist(["ON_DEMAND", "SPOT"]) && ravion_sandbox_pool.this.reserve_policy.type == "FIXED" && ravion_sandbox_pool.this.reserve_policy.value == 2 && ravion_sandbox_pool.this.max_hosts == 25
    error_message = "The pool's markets, warm hosts and host cap must be used as given"
  }
}

run "router_may_publish_metrics_in_its_namespace_only" {
  command = plan

  assert {
    condition     = aws_iam_instance_profile.router.role == aws_iam_role.router.name && aws_iam_instance_profile.router.name == aws_iam_role.router.name && aws_iam_role.router.name == "apps-router" && aws_iam_role.router.path == "/"
    error_message = "The router's instance profile must hold its role under the same name, with no path, so the role follows from the profile name"
  }

  assert {
    condition     = jsondecode(aws_iam_role.router.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "Only EC2 may assume the router's role"
  }

  assert {
    condition     = aws_iam_role_policy.router_metrics.role == aws_iam_role.router.id && length(jsondecode(aws_iam_role_policy.router_metrics.policy).Statement) == 1
    error_message = "The router's role must hold one inline statement"
  }

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.router_metrics.policy).Statement).Effect == "Allow" && one(jsondecode(aws_iam_role_policy.router_metrics.policy).Statement).Action == "cloudwatch:PutMetricData" && one(jsondecode(aws_iam_role_policy.router_metrics.policy).Statement).Resource == "*"
    error_message = "The statement must allow cloudwatch:PutMetricData, which has no resource-level permissions, and nothing else"
  }

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.router_metrics.policy).Statement).Condition == { StringEquals = { "cloudwatch:namespace" = "Ravion/AppRouter" } }
    error_message = "The router must publish metrics only in the Ravion/AppRouter namespace"
  }
}

run "session_manager_access_adds_the_session_manager_core_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.router_ssm) == 1 && aws_iam_role_policy_attachment.router_ssm[0].role == aws_iam_role.router.name
    error_message = "Session Manager access must be on by default"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.router_ssm[0].policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "Session Manager access must attach the Session Manager core policy and no other managed policy"
  }
}

run "session_manager_off_leaves_the_metrics_permission_only" {
  command = plan

  variables {
    ssm_enabled = false
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.router_ssm) == 0 && aws_iam_role_policy.router_metrics.role == aws_iam_role.router.id
    error_message = "Turning Session Manager off must attach no managed policy and keep the metrics permission"
  }
}

run "outputs_feed_the_apps_block" {
  command = plan

  assert {
    condition     = output.execution_environment_id == "ee_test"
    error_message = "execution_environment_id must be the sandbox pool's execution environment"
  }

  assert {
    condition     = output.wildcard_domain_name == "apps.example-apex.test"
    error_message = "wildcard_domain_name must be the certificate's apex, without *."
  }

  assert {
    condition     = output.router_subnet_ids == tolist(["subnet-1a", "subnet-1b"])
    error_message = "router_subnet_ids must be the subnets the router may run in"
  }

  assert {
    condition     = output.router_security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "router_security_group_id must be the router's security group, not the load balancer's"
  }

  assert {
    condition     = output.router_instance_profile_name == "apps-router"
    error_message = "router_instance_profile_name must name the router's instance profile"
  }

  assert {
    condition     = output.traffic_target_group_arn == "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-https/1111111111111111" && output.redirect_target_group_arn == "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/apps-http/2222222222222222"
    error_message = "The target group outputs must be the traffic and redirect target groups"
  }

  assert {
    condition     = output.host_security_group_id == "sg-0cccccccccccccccc"
    error_message = "host_security_group_id must be the sandbox hosts' security group"
  }
}

run "outputs_describe_the_load_balancer_and_where_it_runs" {
  command = plan

  assert {
    condition     = output.load_balancer_dns_name == "apps-1234567890123456.elb.us-east-2.amazonaws.com" && output.load_balancer_zone_id == "ZLMOA37VPKANP" && output.load_balancer_arn == "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/apps/1234567890123456"
    error_message = "The load balancer outputs must describe the load balancer"
  }

  assert {
    condition     = output.load_balancer_arn_suffix == "net/apps/1234567890123456" && output.traffic_target_group_arn_suffix == "targetgroup/apps-https/1111111111111111"
    error_message = "The load balancer and traffic target group must be named the way their CloudWatch metrics are"
  }

  assert {
    condition     = output.aws_account_id == "123456789012" && output.region == "us-east-2"
    error_message = "The account and region outputs must describe where the resources live"
  }
}
