# CloudWatch alarm notification action tests
# Run with: tofu test
#
# The mock provider plans an alarm with no actions as alarm_actions = [], but
# the AWS provider plans it as null. These runs plan against the AWS provider so
# the outputs see the values a real plan produces. The credentials are
# placeholders and every data source is overridden, so planning never calls AWS.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    id   = "us-east-1"
    name = "us-east-1"
  }
}

override_data {
  target = data.aws_elb_service_account.current
  values = {
    arn = "arn:aws:iam::127311923021:root"
  }
}

override_data {
  target = module.security_group.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = module.security_group.data.aws_region.current
  values = {
    id   = "us-east-1"
    name = "us-east-1"
  }
}

variables {
  name       = "test-alb"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-12345678", "subnet-87654321"]
}

run "alarms_without_actions" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = true
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 1
    error_message = "Unhealthy hosts alarm should be planned when alarms are enabled"
  }

  assert {
    condition     = length(output.cloudwatch_alarm_notification_actions.alarm) == 0 && length(output.cloudwatch_alarm_notification_actions.ok) == 0
    error_message = "cloudwatch_alarm_notification_actions should be empty lists when no alarm or OK actions are configured"
  }
}

run "alarms_with_actions" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = true
    cloudwatch_alarm_actions           = ["arn:aws:sns:us-east-1:123456789012:b-alerts", "arn:aws:sns:us-east-1:123456789012:a-alerts"]
    cloudwatch_ok_actions              = ["arn:aws:sns:us-east-1:123456789012:recovered"]
  }

  assert {
    condition     = output.cloudwatch_alarm_notification_actions.alarm == tolist(["arn:aws:sns:us-east-1:123456789012:a-alerts", "arn:aws:sns:us-east-1:123456789012:b-alerts"])
    error_message = "cloudwatch_alarm_notification_actions.alarm should list the configured alarm actions, sorted"
  }

  assert {
    condition     = output.cloudwatch_alarm_notification_actions.ok == tolist(["arn:aws:sns:us-east-1:123456789012:recovered"])
    error_message = "cloudwatch_alarm_notification_actions.ok should list the configured OK actions"
  }
}

run "alarms_disabled" {
  command = plan

  variables {
    cloudwatch_alarms_creation_enabled = false
  }

  assert {
    condition     = length(output.cloudwatch_alarm_notification_actions.alarm) == 0 && length(output.cloudwatch_alarm_notification_actions.ok) == 0
    error_message = "cloudwatch_alarm_notification_actions should be empty lists when alarms are disabled"
  }
}
