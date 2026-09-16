################################################################################
# Service addresses
#
# The in-cluster and load balancer URLs other workloads are pointed at. Both
# are derived from variables the stack already receives plus the listener
# lookup, so they can be checked from a plan against mocked providers.
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
  name                       = "test-workload"
  region                     = "us-east-1"
  vpc_id                     = "vpc-0123456789abcdef0"
  kubernetes_service_enabled = true
  release_name               = "test-workload"
  release_namespace          = "test"
  listener_arn               = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/1234567890abcdef/1234567890abcdef"
}

run "addresses_are_null_for_workloads_without_a_service" {
  command = plan

  variables {
    kubernetes_service_enabled = false
    listener_arn               = null
  }

  assert {
    condition     = output.service_host == null && output.service_port == null && output.service_url == null && output.load_balancer_url == null
    error_message = "Worker and cron stacks render no Service and pass no listener, so they must expose no address at all."
  }
}

run "in_cluster_address_does_not_need_a_load_balancer" {
  command = plan

  variables {
    listener_arn = null
  }

  assert {
    condition     = output.service_url == "http://test-workload.test.svc.cluster.local:8080" && output.service_port == 8080
    error_message = "A cluster-only service must still expose its in-cluster address."
  }

  assert {
    condition     = output.load_balancer_url == null
    error_message = "Without a listener there is no load balancer URL."
  }
}

run "in_cluster_address_names_the_release_service" {
  command = plan

  assert {
    condition     = output.service_host == "test-workload.test.svc.cluster.local"
    error_message = "The in-cluster host must be the release name in the release namespace under svc.cluster.local."
  }

  assert {
    condition     = output.service_port == 8080
    error_message = "The service port must be the container port."
  }

  assert {
    condition     = output.service_url == "http://test-workload.test.svc.cluster.local:8080"
    error_message = "The in-cluster URL must carry the target group protocol, the service host, and the container port."
  }
}

run "in_cluster_address_follows_container_port_and_protocol" {
  command = plan

  variables {
    container_port        = 3000
    target_group_protocol = "HTTPS"
  }

  assert {
    condition     = output.service_url == "https://test-workload.test.svc.cluster.local:3000"
    error_message = "The in-cluster URL must follow the configured container port and target group protocol."
  }
}

run "in_cluster_address_is_null_without_a_release_identity" {
  command = plan

  variables {
    release_name      = null
    release_namespace = null
  }

  assert {
    condition     = output.service_host == null && output.service_url == null
    error_message = "Without a release name and namespace there is no Service to name."
  }

  assert {
    condition     = output.load_balancer_url == "https://test.us-east-1.elb.amazonaws.com"
    error_message = "The load balancer URL does not depend on the release identity."
  }
}

run "load_balancer_url_uses_the_https_listener_and_alb_dns_name" {
  command = plan

  assert {
    condition     = output.load_balancer_url == "https://test.us-east-1.elb.amazonaws.com"
    error_message = "With only a path rule the load balancer URL must be the listener scheme plus the load balancer DNS name, with no port on the scheme default."
  }
}

run "load_balancer_url_prefers_the_first_concrete_host_rule" {
  command = plan

  variables {
    listener_rule_conditions = [
      { type = "host-header", values = ["*.example.com", "app.example.com", "www.example.com"] },
      { type = "path-pattern", values = ["/api/*"] },
    ]
  }

  assert {
    condition     = output.load_balancer_url == "https://app.example.com"
    error_message = "The load balancer URL must use the first host-header value without a wildcard."
  }
}

run "load_balancer_url_falls_back_when_every_host_rule_is_a_wildcard" {
  command = plan

  variables {
    listener_rule_conditions = [
      { type = "host-header", values = ["*.example.com"] },
    ]
  }

  assert {
    condition     = output.load_balancer_url == "https://test.us-east-1.elb.amazonaws.com"
    error_message = "A wildcard host cannot be dialled, so the load balancer URL must fall back to the load balancer DNS name."
  }
}

run "load_balancer_url_carries_a_non_default_http_port" {
  command = plan

  override_data {
    target = data.aws_lb_listener.attached
    values = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1234567890abcdef"
      protocol          = "HTTP"
      port              = 8080
    }
  }

  assert {
    condition     = output.load_balancer_url == "http://test.us-east-1.elb.amazonaws.com:8080"
    error_message = "An HTTP listener on a non-default port must produce an http URL with that port."
  }
}

run "load_balancer_url_omits_the_default_http_port" {
  command = plan

  override_data {
    target = data.aws_lb_listener.attached
    values = {
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/1234567890abcdef"
      protocol          = "HTTP"
      port              = 80
    }
  }

  assert {
    condition     = output.load_balancer_url == "http://test.us-east-1.elb.amazonaws.com"
    error_message = "An HTTP listener on port 80 must produce an http URL with no port."
  }
}

run "load_balancer_subnets_are_published_for_the_ingress_allow_list" {
  command = plan

  assert {
    condition     = output.load_balancer_subnet_cidr_blocks == tolist(["10.0.0.0/20", "10.0.0.0/20"])
    error_message = "With a listener attached the stack must publish one CIDR per load balancer subnet so the workload's NetworkPolicy can admit the load balancer nodes."
  }
}

run "no_load_balancer_means_no_subnet_cidrs" {
  command = plan

  variables {
    listener_arn = null
  }

  assert {
    condition     = length(output.load_balancer_subnet_cidr_blocks) == 0
    error_message = "A cluster-only service has no load balancer subnets to admit."
  }
}

