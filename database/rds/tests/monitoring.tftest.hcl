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
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

variables {
  name                               = "test-db"
  region                             = "us-east-1"
  vpc_id                             = "vpc-12345678"
  subnet_ids                         = ["subnet-11111111", "subnet-22222222"]
  security_group_creation_enabled    = false
  security_group_id                  = "sg-12345678"
  monitoring_interval                = 0
  cloudwatch_alarms_creation_enabled = true
  cloudwatch_alarm_actions           = ["arn:aws:sns:us-east-1:123456789012:alerts"]
  cloudwatch_ok_actions              = ["arn:aws:sns:us-east-1:123456789012:recovery"]
  engine                             = "postgres"
  instance_class                     = "db.t3.micro"
  allocated_storage                  = 20
  username                           = "dbadmin"
}

run "alarms_disabled" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled = false
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.read_iops) == 0 && length(aws_cloudwatch_metric_alarm.write_iops) == 0 && length(output.cloudwatch_alarm_arns) == 0
    error_message = "Disabled monitoring must create no alarms or output ARNs."
  }
}

run "storage_and_io_monitoring" {
  command = plan
  variables {
    cloudwatch_alarm_period               = 10
    cloudwatch_alarm_read_iops_threshold  = 1250
    cloudwatch_alarm_write_iops_threshold = 750
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].metric_name == "ReadIOPS" && aws_cloudwatch_metric_alarm.write_iops[0].metric_name == "WriteIOPS"
    error_message = "Monitor both read and write activity."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].alarm_actions == toset(var.cloudwatch_alarm_actions) && aws_cloudwatch_metric_alarm.write_iops[0].ok_actions == toset(var.cloudwatch_ok_actions)
    error_message = "Forward alarm and recovery actions."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].threshold == 1250 && aws_cloudwatch_metric_alarm.write_iops[0].threshold == 750
    error_message = "Use custom IOPS thresholds."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].period == 60 && aws_cloudwatch_metric_alarm.write_iops[0].period == 60
    error_message = "Do not request sub-minute RDS metrics."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].treat_missing_data == "missing"
    error_message = "Unavailable metrics must not silently report OK."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.read_iops[0].dimensions.DBInstanceIdentifier == "test-db" && aws_cloudwatch_metric_alarm.write_iops[0].statistic == "Average"
    error_message = "Scope IOPS to the primary instance."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.free_storage_space[0].metric_name == "FreeStorageSpace" && aws_cloudwatch_metric_alarm.free_storage_space[0].threshold == 5368709120
    error_message = "Preserve existing RDS storage alarm."
  }
  assert {
    condition     = length(output.cloudwatch_alarm_arns) == 5
    error_message = "Expose old and new alarm ARNs."
  }
}

run "reject_zero_read_iops_threshold" {
  command = plan
  variables {
    cloudwatch_alarm_read_iops_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_read_iops_threshold]
}

run "reject_zero_write_iops_threshold" {
  command = plan
  variables {
    cloudwatch_alarm_write_iops_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_write_iops_threshold]
}
