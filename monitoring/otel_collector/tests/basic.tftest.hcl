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
  # The security-groups module validates referenced group IDs.
  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
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
# Metrics to Amazon Managed Service for Prometheus
################################################################################

run "metrics_to_prometheus_when_chosen" {
  command = plan

  variables {
    metrics_enabled             = true
    metrics_destination         = "prometheus"
    prometheus_remote_write_url = "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/api/v1/remote_write"
    prometheus_workspace_arn    = "arn:aws:aps:us-west-2:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines.metrics.exporters == ["prometheusremotewrite"]
    error_message = "Metrics should be remote-written to Prometheus."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.prometheusremotewrite.endpoint == "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/api/v1/remote_write"
    error_message = "The remote write exporter should send to the workspace's remote write URL."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.prometheusremotewrite.auth.authenticator == "sigv4auth"
    error_message = "Remote writes should be signed with SigV4."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).extensions.sigv4auth == { region = "us-west-2", service = "aps" }
    error_message = "The SigV4 extension should sign for the aps service in the collector's region."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.extensions == ["health_check", "sigv4auth"]
    error_message = "The SigV4 extension should be enabled alongside the health check."
  }

  assert {
    condition     = !contains(keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters), "awsemf")
    error_message = "No CloudWatch metrics exporter should be configured."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.metrics) == 0 && length(aws_iam_role_policy.metrics) == 0
    error_message = "No CloudWatch metric log group or permissions should exist while metrics go to Prometheus."
  }

  assert {
    condition     = data.aws_iam_policy_document.prometheus[0].statement[0].actions == toset(["aps:RemoteWrite"]) && data.aws_iam_policy_document.prometheus[0].statement[0].resources == toset(["arn:aws:aps:us-west-2:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"])
    error_message = "The task role should only be allowed to remote-write to the chosen workspace."
  }

  assert {
    condition     = output.metrics_log_group_name == null
    error_message = "There is no metric log group while metrics go to Prometheus."
  }
}

run "prometheus_destination_is_ignored_while_metrics_are_disabled" {
  command = plan

  variables {
    metrics_destination = "prometheus"
  }

  assert {
    condition     = keys(yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines) == ["traces"]
    error_message = "No metrics pipeline should run while metrics are disabled."
  }

  assert {
    condition     = length(aws_iam_role_policy.prometheus) == 0
    error_message = "No Prometheus permissions should exist while metrics are disabled."
  }
}

run "rejects_prometheus_without_a_remote_write_url" {
  command = plan

  variables {
    metrics_enabled          = true
    metrics_destination      = "prometheus"
    prometheus_workspace_arn = "arn:aws:aps:us-west-2:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.prometheus_remote_write_url]
}

run "rejects_prometheus_without_a_workspace_arn" {
  command = plan

  variables {
    metrics_enabled             = true
    metrics_destination         = "prometheus"
    prometheus_remote_write_url = "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/api/v1/remote_write"
  }

  expect_failures = [var.prometheus_workspace_arn]
}

run "rejects_unknown_metrics_destination" {
  command = plan

  variables {
    metrics_destination = "datadog"
  }

  expect_failures = [var.metrics_destination]
}

################################################################################
# Logs
################################################################################

run "logs_to_cloudwatch_when_enabled" {
  command = plan

  variables {
    logs_enabled = true
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).service.pipelines.logs.exporters == ["awscloudwatchlogs"]
    error_message = "OTLP logs should be exported to CloudWatch Logs."
  }

  assert {
    condition     = yamldecode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value).exporters.awscloudwatchlogs.log_group_name == "/ecs/test-collector/otlp-logs"
    error_message = "OTLP logs should be written to the module's OTLP log group."
  }

  assert {
    condition     = aws_cloudwatch_log_group.otlp_logs[0].name == "/ecs/test-collector/otlp-logs" && aws_cloudwatch_log_group.otlp_logs[0].retention_in_days == 30
    error_message = "The OTLP log group should exist with the same retention as the collector's logs."
  }

  assert {
    condition     = data.aws_iam_policy_document.logs[0].statement[0].actions == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "The task role should only create streams and put events in the OTLP log group."
  }

  assert {
    condition     = output.otlp_log_group_name == "/ecs/test-collector/otlp-logs"
    error_message = "The OTLP log group should be an output."
  }
}

run "no_logs_pipeline_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.otlp_logs) == 0 && length(aws_iam_role_policy.logs) == 0 && output.otlp_log_group_name == null
    error_message = "No OTLP log group, permissions or output should exist while logs are disabled."
  }
}

################################################################################
# Access
################################################################################

run "client_security_group_reaches_the_collector_by_default" {
  command = apply

  assert {
    condition     = length(module.security_group.ingress_rule_ids) == 2
    error_message = "Only the client security group should reach the collector, once per OTLP port."
  }

  assert {
    condition     = length(module.client_security_group.ingress_rule_ids) == 0 && length(module.client_security_group.egress_rule_ids) == 2
    error_message = "The client security group should carry no ingress and egress to the collector on each OTLP port only."
  }

  assert {
    condition     = output.client_security_group_id == module.client_security_group.security_group_id
    error_message = "The client security group should be an output for senders to attach."
  }

  assert {
    condition     = length(module.security_group.egress_rule_ids) == 1
    error_message = "The collector should only be allowed HTTPS egress."
  }
}

run "otlp_ports_open_to_allowed_security_groups_as_well" {
  command = apply

  variables {
    allowed_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa", "sg-0bbbbbbbbbbbbbbbb"]
  }

  assert {
    condition     = length(module.security_group.ingress_rule_ids) == 6
    error_message = "The client security group and each allowed security group should get one rule per OTLP port."
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
