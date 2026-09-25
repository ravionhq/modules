# The default NodePool/EC2NodeClass release is the only place Karpenter's node
# hardening is rendered, so it needs a run with Karpenter actually enabled:
# 0.9.0 shipped a coalesce() that failed every install without a customer KMS key
# because no test turned Karpenter on.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  # The Pod Identity association validates the role ARN it is handed.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:mock", url = "https://sqs.us-east-2.amazonaws.com/123456789012/mock" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}
mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name              = "test-cluster"
  region                    = "us-east-2"
  cluster_security_group_id = "sg-12345678"
  node_subnet_ids           = ["subnet-0a", "subnet-0b"]
  karpenter_enabled         = true
  eso_enabled               = false
  logs_providers            = []
  metrics_providers         = []
  ravion_operator_enabled   = false
}

run "queue_age_monitoring_is_enabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age) == 1 && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].dimensions.QueueName == "karpenter-test-cluster"
    error_message = "Default monitoring must target the provisioned interruption queue."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].metric_name == "ApproximateAgeOfOldestMessage" && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].namespace == "AWS/SQS" && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].statistic == "Maximum" && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].threshold == 60 && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].period == 60 && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].comparison_operator == "GreaterThanOrEqualToThreshold" && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].treat_missing_data == "notBreaching"
    error_message = "Detect a stalled consumer within a single one-minute period without alerting on idle queues."
  }
}
run "custom_queue_and_notifications" {
  command = plan
  variables {
    karpenter_interruption_queue_name                        = "custom-interruptions"
    karpenter_interruption_queue_alarm_age_threshold_seconds = 120
    karpenter_interruption_queue_alarm_actions               = ["arn:aws:sns:us-east-2:123456789012:alerts"]
    karpenter_interruption_queue_alarm_ok_actions            = ["arn:aws:sns:us-east-2:123456789012:recovery"]
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].dimensions.QueueName == "custom-interruptions" && aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].threshold == 120 && contains(aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].alarm_actions, "arn:aws:sns:us-east-2:123456789012:alerts") && contains(aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age[0].ok_actions, "arn:aws:sns:us-east-2:123456789012:recovery")
    error_message = "Overrides must reach the queue dimension, threshold and state-transition actions."
  }
}
run "explicit_opt_out" {
  command = plan
  variables { karpenter_interruption_queue_alarm_creation_enabled = false }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age) == 0 && length(module.karpenter) == 1
    error_message = "Opting out removes only monitoring, not Karpenter."
  }
}
run "no_alarm_without_karpenter" {
  command = plan
  variables { karpenter_enabled = false }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age) == 0
    error_message = "Do not monitor an interruption queue that does not exist."
  }
}
run "reject_threshold_at_retention" {
  command = plan
  variables { karpenter_interruption_queue_alarm_age_threshold_seconds = 300 }
  expect_failures = [aws_cloudwatch_metric_alarm.karpenter_interruption_queue_age]
}
run "reject_nonpositive_threshold" {
  command = plan
  variables { karpenter_interruption_queue_alarm_age_threshold_seconds = 0 }
  expect_failures = [var.karpenter_interruption_queue_alarm_age_threshold_seconds]
}
