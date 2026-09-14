################################################################################
# Service addresses and peer ingress
#
# The Cloud Map address other services call this one at, the load balancer
# URL, and the security group rules that let in-VPC callers reach the
# container port. Everything here is derivable at plan time.
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
      protocol          = "HTTPS"
      port              = 443
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
  mock_resource "aws_service_discovery_service" {
    defaults = {
      arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-abcdef1234567890"
      id  = "srv-abcdef1234567890"
    }
  }
}

variables {
  name        = "test-service"
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
}

run "addresses_are_null_without_discovery_or_load_balancer" {
  command = plan

  assert {
    condition     = output.service_host == null && output.service_port == null && output.service_url == null && output.load_balancer_url == null && output.service_discovery_namespace_name == null
    error_message = "A worker with neither service discovery nor a load balancer must expose no address."
  }

  assert {
    condition     = length(output.security_group_ingress_rules) == 0
    error_message = "Without service discovery no peer ingress rule is added."
  }
}

run "alb_service_registers_an_a_record_and_exposes_its_address" {
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
          values = ["/*"]
        }]
      }]
    }
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = output.service_host == "test-service.test-cluster.internal" && output.service_port == 8080
    error_message = "The in-VPC host must be <name>.<namespace> and the port the container port."
  }

  assert {
    condition     = output.service_url == "http://test-service.test-cluster.internal:8080"
    error_message = "The in-VPC URL must carry the target group protocol, the host, and the port."
  }

  assert {
    condition     = output.service_discovery_namespace_name == "test-cluster.internal"
    error_message = "The namespace name must be exposed alongside the address."
  }

  assert {
    condition     = one(aws_ecs_service.this.service_registries).container_name == null && one(aws_ecs_service.this.service_registries).container_port == null
    error_message = "A records in awsvpc mode must not carry a container name or port."
  }

  assert {
    condition     = output.load_balancer_url == "https://mock-alb-1234567890.us-east-1.elb.amazonaws.com"
    error_message = "With only a path rule the load balancer URL is the listener scheme plus the ALB DNS name, with no port on the scheme default."
  }
}

run "srv_records_keep_the_container_name_and_port" {
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
          values = ["/*"]
        }]
      }]
    }
    service_discovery = {
      namespace_id    = "ns-abcdefghij1234567"
      namespace_name  = "test-cluster.internal"
      dns_record_type = "SRV"
    }
  }

  assert {
    condition     = one(aws_ecs_service.this.service_registries).container_name == "app" && one(aws_ecs_service.this.service_registries).container_port == 8080
    error_message = "SRV records publish the port, so the container name and port must be set."
  }
}

run "service_host_is_lowercased" {
  command = plan

  variables {
    name = "Test-Service"
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = output.service_host == "test-service.test-cluster.internal"
    error_message = "DNS is case-insensitive, so the host must be lowercased."
  }
}

run "service_address_without_a_load_balancer_uses_the_container_port" {
  command = plan

  variables {
    container_port = 3000
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = output.service_url == "http://test-service.test-cluster.internal:3000" && output.load_balancer_url == null
    error_message = "A cluster-only service still exposes its in-VPC address, and has no load balancer URL."
  }
}

run "nlb_service_addresses_carry_the_listener_protocol_and_port" {
  command = plan

  variables {
    deployment_type = "rolling"
    container_port  = 5000
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listeners = [{
        nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
        port            = 6000
        protocol        = "TCP"
        container_port  = 5000
        target_protocol = "TCP"
      }]
    }
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = output.service_url == "tcp://test-service.test-cluster.internal:5000"
    error_message = "The in-VPC URL of a network service uses the target protocol and the container port."
  }

  assert {
    condition     = output.load_balancer_url == "tcp://mock-alb-1234567890.us-east-1.elb.amazonaws.com:6000"
    error_message = "The NLB URL uses the listener protocol, the NLB DNS name, and the listener port."
  }
}

run "load_balancer_url_prefers_the_first_concrete_host_rule" {
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
          type   = "host-header"
          values = ["*.example.com", "api.example.com", "www.example.com"]
          }, {
          type   = "path-pattern"
          values = ["/*"]
        }]
      }]
    }
  }

  assert {
    condition     = output.load_balancer_url == "https://api.example.com"
    error_message = "The load balancer URL must use the first host-header value without a wildcard."
  }
}

run "load_balancer_url_falls_back_when_every_host_rule_is_a_wildcard" {
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
          type   = "host-header"
          values = ["*.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = output.load_balancer_url == "https://mock-alb-1234567890.us-east-1.elb.amazonaws.com"
    error_message = "A wildcard host cannot be dialled, so the URL must fall back to the ALB DNS name."
  }
}

run "load_balancer_url_carries_a_non_default_http_port" {
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
          values = ["/*"]
        }]
      }]
    }
  }

  override_data {
    target = data.aws_lb_listener.attached
    values = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock-alb/1234567890123456"
      protocol          = "HTTP"
      port              = 8080
    }
  }

  assert {
    condition     = output.load_balancer_url == "http://mock-alb-1234567890.us-east-1.elb.amazonaws.com:8080"
    error_message = "An HTTP listener on a non-default port must produce an http URL with that port."
  }
}

run "discovery_admits_the_whole_vpc_on_the_container_port_by_default" {
  command = plan

  variables {
    container_port                  = 8080
    load_balancer_security_group_id = "sg-0000000000000000a"
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
          values = ["/*"]
        }]
      }]
    }
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = length(output.security_group_ingress_rules) == 2
    error_message = "Expected the load balancer rule plus one peer rule."
  }

  assert {
    condition     = output.security_group_ingress_rules[1].cidr_ipv4 == "10.0.0.0/16" && output.security_group_ingress_rules[1].from_port == 8080 && output.security_group_ingress_rules[1].to_port == 8080 && try(output.security_group_ingress_rules[1].referenced_security_group_id, null) == null
    error_message = "The peer rule must admit the VPC CIDR on exactly the container port, after the load balancer rule."
  }
}

run "allowed_security_groups_replace_the_vpc_wide_peer_rule" {
  command = plan

  variables {
    container_port                  = 8080
    load_balancer_security_group_id = "sg-0000000000000000a"
    allowed_security_group_ids      = ["sg-0000000000000000b", "sg-0000000000000000c"]
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
          values = ["/*"]
        }]
      }]
    }
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  assert {
    condition     = length(output.security_group_ingress_rules) == 3
    error_message = "Expected the load balancer rule plus one rule per allowed security group."
  }

  assert {
    condition     = output.security_group_ingress_rules[1].referenced_security_group_id == "sg-0000000000000000b" && output.security_group_ingress_rules[2].referenced_security_group_id == "sg-0000000000000000c"
    error_message = "Each allowed security group gets its own rule, in order."
  }

  assert {
    condition     = alltrue([for rule in output.security_group_ingress_rules : try(rule.cidr_ipv4, null) != "10.0.0.0/16"])
    error_message = "Listing security groups must remove the VPC-wide peer rule, not add to it."
  }
}

run "allowed_security_groups_do_nothing_without_discovery" {
  command = plan

  variables {
    container_port                  = 8080
    load_balancer_security_group_id = "sg-0000000000000000a"
    allowed_security_group_ids      = ["sg-0000000000000000b"]
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
          values = ["/*"]
        }]
      }]
    }
  }

  assert {
    condition     = length(output.security_group_ingress_rules) == 1
    error_message = "Peer rules exist only for services that register a discovery address."
  }
}

run "discovery_rejects_a_name_longer_than_a_dns_label" {
  command = plan

  variables {
    name               = "this-service-name-is-far-too-long-to-be-a-single-dns-label-under-cloud-map"
    execution_role_arn = "arn:aws:iam::123456789012:role/existing-execution-role"
    task_role_arn      = "arn:aws:iam::123456789012:role/existing-task-role"
    service_discovery = {
      namespace_id   = "ns-abcdefghij1234567"
      namespace_name = "test-cluster.internal"
    }
  }

  expect_failures = [aws_service_discovery_service.this]
}
