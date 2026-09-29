################################################################################
# OpenTelemetry Collector Module Tests
################################################################################

# aws_iam_policy_document needs valid JSON: the mock provider's generated
# string fails the provider-side assume_role_policy validation. Computed ARNs
# must look like ARNs for the same reason.
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
      region = "us-west-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:mock"
    }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:us-west-2:123456789012:cluster/mock"
    }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-west-2:123456789012:task-definition/mock:1"
    }
  }
  mock_resource "aws_service_discovery_service" {
    defaults = {
      arn = "arn:aws:servicediscovery:us-west-2:123456789012:service/srv-mock"
    }
  }
}

variables {
  name       = "test-collector"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-1a2b3c4d", "subnet-5e6f7a8b"]
}

################################################################################
# Defaults: traces to X-Ray only
################################################################################

run "traces_to_xray_by_default" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.launch_type == "FARGATE" && aws_ecs_service.this.desired_count == 1
    error_message = "The collector should run one Fargate task by default."
  }

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Collector tasks must never get a public IP."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "512" && aws_ecs_task_definition.this.memory == "1024"
    error_message = "The task should default to 512 CPU units and 1024 MiB."
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "The task should default to ARM64."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == "public.ecr.aws/aws-observability/aws-otel-collector:v0.50.0"
    error_message = "The task should run the pinned AWS Distro for OpenTelemetry collector image."
  }

  assert {
    condition     = [for mapping in jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings : mapping.containerPort] == [4317, 4318]
    error_message = "The container should expose OTLP gRPC on 4317 and OTLP HTTP on 4318 only."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.command == ["CMD", "/healthcheck"]
    error_message = "The container health check should run the collector's /healthcheck binary."
  }

  assert {
    condition     = keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines) == ["traces"]
    error_message = "Only the traces pipeline should run by default."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines.traces.exporters == ["awsxray"]
    error_message = "Traces should be exported to X-Ray."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awsxray.region == "us-west-2"
    error_message = "The X-Ray exporter should send to the collector's region."
  }

  assert {
    condition     = keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters) == ["awsxray"]
    error_message = "No metrics exporter should be configured by default."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.metrics) == 0 && length(aws_iam_role_policy.metrics) == 0
    error_message = "No metric log group or metric permissions should exist while metrics are disabled."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.xray.statement[0].actions) == toset(["xray:PutTraceSegments", "xray:PutTelemetryRecords"])
    error_message = "The task role should only be allowed to write to X-Ray."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/ecs/test-collector" && aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "The collector's logs should go to /ecs/<name> with 30-day retention."
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this.name == "test-collector.internal" && aws_service_discovery_private_dns_namespace.this.vpc == "vpc-12345678"
    error_message = "The private DNS namespace should be <name>.internal in the collector's VPC."
  }

  assert {
    condition     = output.otlp_grpc_endpoint == "http://otlp.test-collector.internal:4317" && output.otlp_http_endpoint == "http://otlp.test-collector.internal:4318"
    error_message = "The endpoints should point at otlp.<name>.internal."
  }
}

################################################################################
# Metrics to CloudWatch
################################################################################

run "metrics_to_cloudwatch_when_enabled" {
  command = plan

  variables {
    metrics_enabled = true
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines.metrics.exporters == ["awsemf"]
    error_message = "Metrics should be exported through the embedded metric format exporter."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awsemf.log_group_name == "/ecs/test-collector/metrics"
    error_message = "Metrics should be written to the module's metric log group."
  }

  assert {
    condition     = !contains(keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awsemf), "namespace")
    error_message = "Without a namespace the exporter should derive one from each sender."
  }

  assert {
    condition     = aws_cloudwatch_log_group.metrics[0].name == "/ecs/test-collector/metrics" && aws_cloudwatch_log_group.metrics[0].retention_in_days == 30
    error_message = "The metric log group should exist with the same retention as the collector's logs."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.metrics[0].statement[0].actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "The task role should only create streams and put events in the metric log group."
  }

  assert {
    condition     = length(aws_iam_role_policy.metrics) == 1
    error_message = "The metric permissions should be attached to the task role."
  }
}

run "metrics_namespace_is_passed_through" {
  command = plan

  variables {
    metrics_enabled   = true
    metrics_namespace = "Checkout/Service"
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awsemf.namespace == "Checkout/Service"
    error_message = "The configured namespace should be set on the exporter."
  }
}

run "blank_metrics_namespace_is_unset" {
  command = plan

  variables {
    metrics_enabled   = true
    metrics_namespace = " "
  }

  assert {
    condition     = !contains(keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awsemf), "namespace")
    error_message = "A blank namespace should be treated as unset."
  }
}

################################################################################
# Access
################################################################################

run "otlp_ports_open_only_to_allowed_security_groups" {
  command = apply

  variables {
    allowed_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa", "sg-0bbbbbbbbbbbbbbbb"]
  }

  assert {
    condition     = length(module.security_group.ingress_rule_ids) == 4
    error_message = "Each allowed security group should get one rule per OTLP port."
  }

  assert {
    condition     = length(module.security_group.egress_rule_ids) == 1
    error_message = "The collector should only be allowed HTTPS egress."
  }
}

run "no_ingress_without_allowed_security_groups" {
  command = apply

  assert {
    condition     = length(module.security_group.ingress_rule_ids) == 0
    error_message = "Without allowed security groups nothing may reach the collector."
  }
}

################################################################################
# Sizing and retention
################################################################################

run "sizing_is_configurable" {
  command = plan

  variables {
    task_cpu           = 1024
    task_memory        = 2048
    cpu_architecture   = "X86_64"
    desired_count      = 2
    log_retention_days = 0
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "1024" && aws_ecs_task_definition.this.memory == "2048"
    error_message = "The task should use the configured size."
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "The task should use the configured architecture."
  }

  assert {
    condition     = aws_ecs_service.this.desired_count == 2
    error_message = "The service should run the configured number of tasks."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == null
    error_message = "A retention of 0 should keep logs indefinitely."
  }
}

################################################################################
# Validation
################################################################################

run "longest_name_fits_iam_and_dns_limits" {
  command = plan

  variables {
    name = "collector-name-that-uses-all-fifty-four-characters-xyz"
  }

  assert {
    condition     = length(aws_iam_role.execution.name) == 64
    error_message = "The longest name should still produce an execution role name within IAM's 64-character limit."
  }

  assert {
    condition     = length(split(".", aws_service_discovery_private_dns_namespace.this.name)[0]) <= 63
    error_message = "The longest name should still be a valid DNS label."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_54_characters" {
  command = plan

  variables {
    name = "a-name-that-is-much-longer-than-fifty-four-characters-x"
  }

  expect_failures = [var.name]
}

run "rejects_empty_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_invalid_allowed_security_group" {
  command = plan

  variables {
    allowed_security_group_ids = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_security_group_ids]
}

run "rejects_invalid_task_cpu" {
  command = plan

  variables {
    task_cpu = 300
  }

  expect_failures = [var.task_cpu]
}

run "rejects_invalid_cpu_architecture" {
  command = plan

  variables {
    cpu_architecture = "arm64"
  }

  expect_failures = [var.cpu_architecture]
}

run "rejects_zero_desired_count" {
  command = plan

  variables {
    desired_count = 0
  }

  expect_failures = [var.desired_count]
}

run "rejects_unsupported_log_retention" {
  command = plan

  variables {
    log_retention_days = 2
  }

  expect_failures = [var.log_retention_days]
}
