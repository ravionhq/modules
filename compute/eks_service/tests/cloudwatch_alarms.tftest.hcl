################################################################################
# CloudWatch alarms
#
# A web workload owns its target group, so it is the only place that can alarm
# on UnHealthyHostCount, which ALB publishes per target group. The alarm uses
# the plain LoadBalancer + TargetGroup dimensions rather than a query, so tools
# that read alarm metrics and dimensions recognise it.
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
      arn_suffix = "app/test/1234567890abcdef"
      dns_name   = "test.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/1234567890abcdef"
      arn_suffix = "targetgroup/test/1234567890abcdef"
    }
  }
}

mock_provider "ravion" {}

variables {
  name                       = "test-workload"
  region                     = "us-east-1"
  vpc_id                     = "vpc-0123456789abcdef0"
  kubernetes_service_enabled = true
  release_name               = "test-workload"
  release_namespace          = "test"
  listener_arn               = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test/1234567890abcdef/1234567890abcdef"
}

run "unhealthy_hosts_alarm_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 1
    error_message = "A load-balanced workload must get an unhealthy hosts alarm by default."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].alarm_name == "test-workload-tg-unhealthy-hosts"
    error_message = "The alarm name must be derived from the target group name."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].metric_name == "UnHealthyHostCount" && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].namespace == "AWS/ApplicationELB" && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].statistic == "Maximum"
    error_message = "The alarm must watch the period maximum of UnHealthyHostCount."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].dimensions.LoadBalancer == "app/test/1234567890abcdef" && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].dimensions.TargetGroup == "targetgroup/test/1234567890abcdef"
    error_message = "The alarm must be scoped to this workload's target group on its load balancer."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].comparison_operator == "GreaterThanThreshold" && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].threshold == 0
    error_message = "By default the first unhealthy target must breach."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].period == 300 && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].treat_missing_data == "notBreaching"
    error_message = "The alarm must use the default period, evaluation periods and missing-data handling."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts[0].alarm_actions) == 0 && length(aws_cloudwatch_metric_alarm.unhealthy_hosts[0].ok_actions) == 0
    error_message = "No actions are set unless configured."
  }
}

run "unhealthy_hosts_alarm_custom_settings" {
  command = plan

  variables {
    cloudwatch_alarm_unhealthy_hosts_threshold = 1
    cloudwatch_alarm_evaluation_periods        = 3
    cloudwatch_alarm_period                    = 60
    cloudwatch_alarm_actions                   = ["arn:aws:sns:us-east-1:123456789012:alerts"]
    cloudwatch_ok_actions                      = ["arn:aws:sns:us-east-1:123456789012:recovery"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].threshold == 1 && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].period == 60
    error_message = "Threshold, evaluation periods and period must follow the inputs."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:alerts"]) && aws_cloudwatch_metric_alarm.unhealthy_hosts[0].ok_actions == toset(["arn:aws:sns:us-east-1:123456789012:recovery"])
    error_message = "Alarm and recovery actions must be forwarded."
  }
  assert {
    condition     = output.cloudwatch_alarm_arns.unhealthy_hosts == aws_cloudwatch_metric_alarm.unhealthy_hosts[0].arn
    error_message = "The alarm ARN must be exposed."
  }
}

run "alarm_name_follows_target_group_override" {
  command = plan

  variables {
    target_group_name = "other-api-tg"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts[0].alarm_name == "other-api-tg-unhealthy-hosts"
    error_message = "Two workloads sharing var.name but not a target group must not share an alarm."
  }
}

run "alarm_name_stays_bounded_for_long_names" {
  command = plan

  variables {
    name = "a${join("", [for i in range(254) : "b"])}"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts[0].alarm_name) <= 255
    error_message = "The alarm name must fit CloudWatch's 255-character limit for any valid workload name."
  }
}

run "no_alarm_when_disabled" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = false
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 0 && length(output.cloudwatch_alarm_arns) == 0
    error_message = "Disabled alarms must create nothing."
  }
}

run "no_alarm_without_load_balancer" {
  command = plan

  variables {
    listener_arn = null
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 0 && length(output.cloudwatch_alarm_arns) == 0
    error_message = "A workload without a target group has no unhealthy hosts to alarm on."
  }
}

run "reject_negative_threshold" {
  command = plan

  variables {
    cloudwatch_alarm_unhealthy_hosts_threshold = -1
  }

  expect_failures = [var.cloudwatch_alarm_unhealthy_hosts_threshold]
}

run "reject_sub_minute_period" {
  command = plan

  variables {
    cloudwatch_alarm_period = 10
  }

  expect_failures = [var.cloudwatch_alarm_period]
}

run "reject_non_arn_action" {
  command = plan

  variables {
    cloudwatch_alarm_actions = ["alerts"]
  }

  expect_failures = [var.cloudwatch_alarm_actions]
}
