# ALB variable validation tests

mock_provider "aws" {
  override_resource {
    target = aws_lb.this
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-alb/1234567890123456"
    }
  }
}

variables {
  name       = "test-alb"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-12345678", "subnet-87654321"]
}

run "duplicate_ingress_security_groups" {
  command = plan

  variables {
    ingress_security_group_ids = ["sg-0123456789abcdef0", "sg-0123456789abcdef0"]
  }

  expect_failures = [var.ingress_security_group_ids]
}

run "invalid_cloudwatch_alarm_period" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = true
    cloudwatch_alarm_period            = 120
  }

  expect_failures = [var.cloudwatch_alarm_period]
}

run "invalid_cloudwatch_alarm_evaluation_periods" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled  = true
    cloudwatch_alarm_evaluation_periods = 0
  }

  expect_failures = [var.cloudwatch_alarm_evaluation_periods]
}

run "invalid_cloudwatch_alarm_target_response_time_threshold" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled              = true
    cloudwatch_alarm_target_response_time_threshold = 0
  }

  expect_failures = [var.cloudwatch_alarm_target_response_time_threshold]
}
