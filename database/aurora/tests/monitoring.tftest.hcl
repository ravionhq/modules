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
  engine                             = "aurora-mysql"
  instance_class                     = "db.serverless"
  engine_version                     = "8.0.mysql_aurora.3.08.2"
  master_username                    = "dbadmin"
  serverless_v2_scaling              = { min_capacity = 0.5, max_capacity = 4 }
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
    condition     = keys(aws_cloudwatch_metric_alarm.read_iops[0].dimensions) == tolist(["DBClusterIdentifier"]) && aws_cloudwatch_metric_alarm.read_iops[0].statistic == "Maximum"
    error_message = "Monitor the busiest cluster instance, including readers."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cluster_storage[0].metric_name == "AuroraVolumeBytesLeftTotal" && aws_cloudwatch_metric_alarm.cluster_storage[0].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.cluster_storage[0].threshold == 107374182400
    error_message = "Serverless MySQL must use actual remaining cluster volume space."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cluster_storage[0].period == 300 && aws_cloudwatch_metric_alarm.cluster_storage[0].statistic == "Minimum"
    error_message = "Storage must use five-minute minimum space."
  }
  assert {
    condition     = length(output.cloudwatch_alarm_arns) == 6
    error_message = "Expose old and new alarm ARNs."
  }
}

run "postgres_serverless_storage" {
  command = plan
  variables {
    engine                                       = "aurora-postgresql"
    engine_version                               = "16.4"
    cloudwatch_alarm_volume_bytes_used_threshold = 109951162777600
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cluster_storage[0].metric_name == "VolumeBytesUsed" && aws_cloudwatch_metric_alarm.cluster_storage[0].comparison_operator == "GreaterThanThreshold" && aws_cloudwatch_metric_alarm.cluster_storage[0].threshold == 109951162777600
    error_message = "PostgreSQL must monitor used volume against the configured limit."
  }
}

run "postgres_provisioned_storage" {
  command = plan
  variables {
    engine                                       = "aurora-postgresql"
    engine_version                               = "16.4"
    cloudwatch_alarm_volume_bytes_used_threshold = 109951162777600
    serverless_v2_scaling                        = null
    instance_class                               = "db.r6g.large"
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cluster_storage[0].metric_name == "VolumeBytesUsed" && aws_cloudwatch_metric_alarm.cluster_storage[0].comparison_operator == "GreaterThanThreshold" && aws_cloudwatch_metric_alarm.cluster_storage[0].threshold == 109951162777600
    error_message = "PostgreSQL must monitor used volume against the configured limit."
  }
}

run "mysql_provisioned_storage" {
  command = plan
  variables {
    serverless_v2_scaling              = null
    instance_class                     = "db.r6g.large"
    cloudwatch_alarm_storage_threshold = 53687091200
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cluster_storage[0].metric_name == "AuroraVolumeBytesLeftTotal" && aws_cloudwatch_metric_alarm.cluster_storage[0].threshold == 53687091200
    error_message = "Provisioned MySQL must use the configured remaining-space threshold."
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

run "reject_zero_storage_threshold" {
  command = plan
  variables {
    cloudwatch_alarm_storage_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_storage_threshold]
}

run "reject_zero_volume_bytes_used_threshold" {
  command = plan
  variables {
    cloudwatch_alarm_volume_bytes_used_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_volume_bytes_used_threshold]
}
