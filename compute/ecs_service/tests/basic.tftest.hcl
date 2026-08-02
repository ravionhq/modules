################################################################################
# Basic ECS Service Module Tests
################################################################################

# Mock provider for testing.
# aws_iam_policy_document data sources need explicit json overrides —
# the mock provider's generated string is not valid JSON and fails the
# provider-side assume_role_policy validation at plan time.
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
}

# These runs leave cluster_parent_fqdn unset, so ravion_domains.tf creates no
# ravion resources. Terraform still configures the ravion provider because the
# module declares it, so an empty mock prevents its real Configure (which
# requires RAVION_API_KEY) from failing the plan.
mock_provider "ravion" {}

################################################################################
# Variables for Tests
################################################################################

variables {
  name        = "test-service"
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
}

################################################################################
# Test: Basic Service Creation
################################################################################

run "basic_service" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == "test-service"
    error_message = "Service name should be 'test-service'"
  }

  assert {
    condition     = aws_ecs_task_definition.this.family == "test-service"
    error_message = "Task definition family should be 'test-service'"
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256"
    error_message = "Default CPU should be 256"
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "512"
    error_message = "Default memory should be 512"
  }

  assert {
    condition     = module.security_group.security_group_vpc_id == "vpc-12345678"
    error_message = "Security group should be in the correct VPC"
  }
}

################################################################################
# Test: Service with Load Balancer
################################################################################

run "service_with_load_balancer" {
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
          values = ["/api/*"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1 && length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create the production + alternate target group pair whenever a load balancer is attached"
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].port == 8080 && aws_lb_target_group.tg_2[0].port == 8080
    error_message = "Target group port should be 8080"
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].protocol == "HTTP"
    error_message = "Target group protocol should be HTTP"
  }

  assert {
    condition     = length(aws_iam_role.ecs_infrastructure) == 1
    error_message = "Should create the ECS infrastructure role whenever a load balancer is attached"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ecs_infrastructure_elb[0].policy_arn == "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
    error_message = "ECS infrastructure role should attach the documented AWS-managed load-balancer policy ARN"
  }

  # Backward-compatible aliases for pre-traffic-shift callers.
  assert {
    condition     = output.target_group_name == output.production_target_group_name
    error_message = "target_group_name should alias the production target group name output"
  }
}

################################################################################
# Test: Rolling service with multiple NLB listeners
################################################################################

run "rolling_service_with_multiple_nlb_listeners" {
  command = plan

  variables {
    deployment_type                   = "rolling"
    container_port                    = 5000
    load_balancer_security_group_id   = "sg-12345678"
    load_balancer_ingress_cidr_blocks = ["0.0.0.0/0"]
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listeners = [
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5000
          protocol        = "TCP"
          container_port  = 5000
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5443
          protocol        = "TLS"
          container_port  = 5443
          target_protocol = "TLS"
          certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        },
      ]
    }
  }

  assert {
    condition     = aws_lb_listener.nlb[0].port == 5000 && aws_lb_listener.nlb_additional["5443"].port == 5443
    error_message = "Should create the primary and additional NLB listeners on their configured ports"
  }

  assert {
    condition     = aws_lb_target_group.tg_1[0].protocol == "TCP" && aws_lb_target_group.nlb_additional["5443"].protocol == "TLS"
    error_message = "Should create one target group per listener with its configured target protocol"
  }

  assert {
    condition     = length(aws_lb_target_group.tg_2) == 0 && length(aws_iam_role.ecs_infrastructure) == 0
    error_message = "Rolling multi-listener services should omit traffic-shift-only target groups and IAM infrastructure"
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings) == 2
    error_message = "Should expose every listener container port in the placeholder task definition"
  }

  assert {
    condition     = toset(keys(output.nlb_listener_arns)) == toset(["5000", "5443"]) && toset(keys(output.nlb_target_group_arns)) == toset(["5000", "5443"])
    error_message = "Should export listener and target group ARNs keyed by listener port"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.nlb_listener_ipv4["0.0.0.0/0"].from_port == 5000
    error_message = "Primary listener ingress should preserve the legacy CIDR-only state key during upgrades"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.nlb_additional_listener_ipv4["5443|0.0.0.0/0"].from_port == 5443
    error_message = "Additional listener ingress should use a listener-port and CIDR state key"
  }
}

run "traffic_shift_rejects_nlb_listeners" {
  command = plan

  variables {
    deployment_type = "blue_green"
    container_port  = 5000
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listeners = [
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5000
          protocol        = "TCP"
          container_port  = 5000
          target_protocol = "TCP"
        },
      ]
    }
  }

  expect_failures = [aws_ecs_service.this]
}

run "service_rejects_legacy_nlb_listener" {
  command = plan

  variables {
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listener = {
        nlb_arn  = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
        port     = 5000
        protocol = "TCP"
      }
    }
  }

  expect_failures = [var.load_balancer_attachment]
}

run "service_rejects_more_than_five_nlb_listeners" {
  command = plan

  variables {
    container_port = 5000
    load_balancer_attachment = {
      target_group = {
        port     = 5000
        protocol = "TCP"
      }
      nlb_listeners = [
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5000
          protocol        = "TCP"
          container_port  = 6000
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5001
          protocol        = "TCP"
          container_port  = 6001
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5002
          protocol        = "TCP"
          container_port  = 6002
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5003
          protocol        = "TCP"
          container_port  = 6003
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5004
          protocol        = "TCP"
          container_port  = 6004
          target_protocol = "TCP"
        },
        {
          nlb_arn         = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/my-nlb/1234567890123456"
          port            = 5005
          protocol        = "TCP"
          container_port  = 6005
          target_protocol = "TCP"
        },
      ]
    }
  }

  expect_failures = [var.load_balancer_attachment]
}

################################################################################
# Test: Service with Load Balancer (Auto Priority)
################################################################################

run "service_with_load_balancer_auto_priority" {
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
        conditions = [{
          type   = "path-pattern"
          values = ["/api/*"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1 && length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create the production + alternate target group pair whenever a load balancer is attached"
  }

  assert {
    condition     = var.load_balancer_attachment.listener_rules[0].priority == null
    error_message = "Priority should default to null so AWS auto-assigns it"
  }
}

################################################################################
# Test: Blue/Green Deployment
################################################################################

run "blue_green_deployment" {
  command = plan

  variables {
    deployment_type = "blue_green"
    container_port  = 8080
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
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1
    error_message = "Should create production target group for blue/green deployment"
  }

  assert {
    condition     = length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create alternate target group for blue/green deployment"
  }

  assert {
    condition     = length(aws_iam_role.ecs_infrastructure) == 1
    error_message = "Should create the ECS infrastructure role for native traffic-shift strategies"
  }

  assert {
    condition     = length(aws_lb_listener_rule.alb["0"].action[0].forward) == 0
    error_message = "Without target-group stickiness the rule should use a plain forward (no group-stickiness block)"
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.test[0].condition : c if length([for q in c.query_string : q if q.key == "__x-rvn-test__" && q.value == "1"]) > 0]) == 1
    error_message = "Test (green) rule should distinguish traffic by the __x-rvn-test__ query string by default"
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.test[0].condition : c if length(c.http_header) > 0]) == 0
    error_message = "Default (query-string) selector should not emit an http_header condition on the test rule"
  }
}

################################################################################
# Test: Header selector for the green test rule
#
# test_traffic_condition_type = "header" swaps the distinguishing test
# condition from the default query string to an HTTP header so requests
# carrying <name>:<value> reach the green target group.
################################################################################

run "green_rule_header_selector" {
  command = plan

  variables {
    deployment_type             = "blue_green"
    container_port              = 8080
    test_traffic_condition_type = "header"
    test_header_name            = "X-Ravion-Test"
    test_header_value           = "1"
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
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.test[0].condition : c if length(c.http_header) > 0 && c.http_header[0].http_header_name == "X-Ravion-Test"]) == 1
    error_message = "Test (green) rule should distinguish traffic by the X-Ravion-Test header when selector is header"
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.test[0].condition : c if length(c.query_string) > 0]) == 0
    error_message = "Header selector should not emit a query-string condition on the test rule"
  }
}

################################################################################
# Test: Sticky target groups require group-level stickiness on the rules
#
# ECS rewrites the production/test rules into a weighted forward across
# tg-1 + tg-2 during traffic-shift deployments; ELBv2 rejects that
# rewrite at PRE_SCALE_UP when the target groups have target-level
# stickiness but the rule's forward action lacks group stickiness.
################################################################################

run "sticky_target_groups_enable_group_stickiness" {
  command = plan

  variables {
    deployment_type                 = "blue_green"
    container_port                  = 8080
    green_alb_listener_rule_enabled = true
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
        stickiness = {
          enabled         = true
          type            = "lb_cookie"
          cookie_duration = 3600
        }
      }
      listener_rules = [{
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
        priority     = 100
        conditions = [{
          type   = "host-header"
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = aws_lb_listener_rule.alb["0"].action[0].target_group_arn == null
    error_message = "Sticky target groups should switch the production rule to the expanded forward block"
  }

  assert {
    condition     = aws_lb_listener_rule.alb["0"].action[0].forward[0].stickiness[0].enabled && aws_lb_listener_rule.alb["0"].action[0].forward[0].stickiness[0].duration == 3600
    error_message = "Production rule forward action should enable group stickiness with the target-group cookie duration"
  }

  assert {
    condition     = aws_lb_listener_rule.test[0].action[0].forward[0].stickiness[0].enabled && aws_lb_listener_rule.test[0].action[0].forward[0].stickiness[0].duration == 3600
    error_message = "Test (green) rule forward action should enable group stickiness with the target-group cookie duration"
  }
}

################################################################################
# Test: Native traffic-shift strategies reject multiple listener rules
#
# advanced_configuration accepts a single production listener rule, so
# ECS would only ever shift traffic on the first rule — additional
# rules would silently keep serving the old revision.
################################################################################

run "blue_green_rejects_multiple_listener_rules" {
  command = plan

  variables {
    deployment_type = "blue_green"
    container_port  = 8080
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
      }
      listener_rules = [
        {
          listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
          priority     = 100
          conditions = [{
            type   = "host-header"
            values = ["api.example.com"]
          }]
        },
        {
          listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
          priority     = 101
          conditions = [{
            type   = "host-header"
            values = ["www.example.com"]
          }]
        },
      ]
    }
  }

  expect_failures = [aws_ecs_service.this]
}

################################################################################
# Test: Canary Deployment
################################################################################

run "canary_deployment" {
  command = plan

  variables {
    deployment_type = "canary"
    container_port  = 8080
    deployment_strategy_config = {
      bake_time_in_minutes = 15
      canary = {
        canary_percent              = 10.0
        canary_bake_time_in_minutes = 5
      }
    }
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
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1 && length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create production + alternate target groups for canary deployment"
  }
}

################################################################################
# Test: Linear Deployment
################################################################################

run "linear_deployment" {
  command = plan

  variables {
    deployment_type = "linear"
    container_port  = 8080
    deployment_strategy_config = {
      bake_time_in_minutes = 10
      linear = {
        step_percent              = 20.0
        step_bake_time_in_minutes = 5
      }
    }
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
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1 && length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create production + alternate target groups for linear deployment"
  }
}

################################################################################
# Test: Auto Scaling
################################################################################

run "service_with_auto_scaling" {
  command = plan

  variables {
    auto_scaling = {
      min_capacity = 1
      max_capacity = 10
      target_tracking = [{
        policy_name       = "cpu-scaling"
        target_value      = 70
        predefined_metric = "ECSServiceAverageCPUUtilization"
      }]
    }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1
    error_message = "Should create auto scaling target"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].min_capacity == 1
    error_message = "Auto scaling min capacity should be 1"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].max_capacity == 10
    error_message = "Auto scaling max capacity should be 10"
  }
}

################################################################################
# Test: Custom Task Configuration
################################################################################

run "custom_task_configuration" {
  command = plan

  variables {
    task_cpu       = 1024
    task_memory    = 2048
    container_port = 3000
    launch_type    = "FARGATE"

    runtime_platform = {
      operating_system_family = "LINUX"
      cpu_architecture        = "ARM64"
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "1024"
    error_message = "Task CPU should be 1024"
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "2048"
    error_message = "Task memory should be 2048"
  }
}

run "ephemeral_storage_requires_fargate_task_compatibility" {
  command = plan

  variables {
    task_ephemeral_storage_size_gib = 21
    requires_compatibilities        = ["EC2"]
  }

  expect_failures = [var.task_ephemeral_storage_size_gib]
}

################################################################################
# Test: IAM Role Creation
################################################################################

run "iam_role_creation" {
  command = plan

  assert {
    condition     = length(aws_iam_role.execution) == 1
    error_message = "Should create execution role when not provided"
  }

  assert {
    condition     = length(aws_iam_role.task) == 1
    error_message = "Should create task role when not provided"
  }
}

run "task_role_inline_policies_allow_mixed_document_shapes" {
  command = plan

  variables {
    task_role_inline_policies = {
      wildcard = {
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream"]
          Resource = "*"
        }]
      }
      bucket_read = {
        Version = "2012-10-17"
        Statement = [{
          Effect = "Allow"
          Action = ["s3:GetObject"]
          Resource = [
            "arn:aws:s3:::bucket-one/*",
            "arn:aws:s3:::bucket-two/*",
          ]
        }]
      }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.task_inline) == 2
    error_message = "Should create both task role inline policies"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_inline["wildcard"].policy).Statement[0].Resource == "*"
    error_message = "Should preserve a string Resource value"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task_inline["bucket_read"].policy).Statement[0].Resource == ["arn:aws:s3:::bucket-one/*", "arn:aws:s3:::bucket-two/*"]
    error_message = "Should preserve a list Resource value"
  }
}

run "task_role_inline_policies_reject_non_object_values" {
  command = plan

  variables {
    task_role_inline_policies = ["not-an-object"]
  }

  expect_failures = [var.task_role_inline_policies]
}

################################################################################
# Test: ECS Exec Enabled
################################################################################

run "ecs_exec_enabled" {
  command = plan

  variables {
    execute_command_enabled = true
  }

  assert {
    condition     = aws_ecs_service.this.enable_execute_command == true
    error_message = "ECS Exec should be enabled"
  }

  assert {
    condition     = length(aws_iam_role_policy.task_exec_command) == 1
    error_message = "Should create ECS Exec IAM policy"
  }
}

################################################################################
# Test: Default Container Port
################################################################################

run "default_container_port" {
  command = plan

  assert {
    condition     = output.container_port == 3000
    error_message = "Default container port should be dummy value 3000 when load balancer is not connected"
  }

  assert {
    condition     = output.container_name == "app"
    error_message = "Container name should be 'app'"
  }
}
