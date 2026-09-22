mock_provider "aws" {}

variables {
  name                  = "test-lambda"
  region                = "us-east-1"
  package_type          = "Zip"
  runtime               = "nodejs20.x"
  handler               = "index.handler"
  s3_bucket             = "artifact-bucket"
  s3_key                = "lambda.zip"
  role_creation_enabled = false
  role_arn              = "arn:aws:iam::123456789012:role/existing-lambda-role"
}

run "disabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 0 && length(output.cloudwatch_alarm_arns) == 0
    error_message = "Direct Terraform callers must opt into alarms."
  }
}

run "regional_error_percentage" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled    = true
    cloudwatch_alarm_error_rate_threshold = 2.5
    cloudwatch_alarm_period               = 60
    cloudwatch_alarm_evaluation_periods   = 3
    cloudwatch_alarm_actions              = ["arn:aws:sns:us-east-1:123456789012:alerts"]
    cloudwatch_ok_actions                 = ["arn:aws:sns:us-east-1:123456789012:recovery"]
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 1 && aws_cloudwatch_metric_alarm.error_rate["us-east-1"].threshold == 2.5 && aws_cloudwatch_metric_alarm.error_rate["us-east-1"].evaluation_periods == 3
    error_message = "Use the configured threshold and evaluation window in the function Region."
  }
  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.error_rate["us-east-1"].metric_query : q if q.return_data]).expression == "IF(invocations > 0, 100 * errors / invocations, 0)"
    error_message = "Alarm on percentage, guarding division by zero, with only the expression returned."
  }
  assert {
    condition     = toset([for q in aws_cloudwatch_metric_alarm.error_rate["us-east-1"].metric_query : q.id]) == toset(["errors", "invocations", "error_rate"]) && alltrue([for m in flatten([for q in aws_cloudwatch_metric_alarm.error_rate["us-east-1"].metric_query : q.metric]) : m.stat == "Sum" && m.period == 60 && m.namespace == "AWS/Lambda" && m.dimensions.FunctionName == "test-lambda"])
    error_message = "Use sums over matching periods and the unqualified regional function name."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["us-east-1"].alarm_actions == toset(var.cloudwatch_alarm_actions) && aws_cloudwatch_metric_alarm.error_rate["us-east-1"].ok_actions == toset(var.cloudwatch_ok_actions)
    error_message = "Wire alarm and recovery notifications."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["us-east-1"].treat_missing_data == "notBreaching"
    error_message = "Idle functions should not alert on missing data."
  }
}

run "edge_execution_regions" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled  = true
    lambda_at_edge_enabled              = true
    version_publishing_enabled          = true
    cloudwatch_alarm_additional_regions = ["us-west-2", "us-east-1", "us-west-2"]
    cloudwatch_alarm_actions            = ["arn:aws:sns:us-east-1:123456789012:east"]
    cloudwatch_alarm_actions_by_region  = { us-west-2 = ["arn:aws:sns:us-west-2:123456789012:west"] }
    cloudwatch_ok_actions_by_region     = { us-west-2 = ["arn:aws:sns:us-west-2:123456789012:recovery"] }
  }
  assert {
    condition     = toset(keys(output.cloudwatch_alarm_arns)) == toset(["us-east-1", "us-west-2"]) && aws_cloudwatch_metric_alarm.error_rate["us-west-2"].region == "us-west-2"
    error_message = "Always include the origin, deduplicate Regions and create each alarm in its execution Region."
  }
  assert {
    condition     = alltrue([for m in flatten([for a in aws_cloudwatch_metric_alarm.error_rate : flatten([for q in a.metric_query : q.metric])]) : m.dimensions.FunctionName == "us-east-1.test-lambda"])
    error_message = "Edge metrics require the origin Region prefix in every execution Region."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["us-west-2"].alarm_actions == toset(["arn:aws:sns:us-west-2:123456789012:west"]) && aws_cloudwatch_metric_alarm.error_rate["us-east-1"].alarm_actions == toset(var.cloudwatch_alarm_actions) && aws_cloudwatch_metric_alarm.error_rate["us-west-2"].ok_actions == toset(["arn:aws:sns:us-west-2:123456789012:recovery"])
    error_message = "Use per-Region overrides without sending to a topic in the wrong Region."
  }
}

run "null_hidden_inputs_use_defaults" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled    = true
    cloudwatch_alarm_error_rate_threshold = null
    cloudwatch_alarm_evaluation_periods   = null
    cloudwatch_alarm_period               = null
    cloudwatch_alarm_additional_regions   = null
    cloudwatch_alarm_actions              = null
    cloudwatch_alarm_actions_by_region    = null
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["us-east-1"].threshold == 1 && aws_cloudwatch_metric_alarm.error_rate["us-east-1"].evaluation_periods == 1
    error_message = "Null hidden definition values must retain safe Terraform defaults."
  }
}

run "reject_zero_rate" {
  command = plan
  variables {
    cloudwatch_alarm_error_rate_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_error_rate_threshold]
}

run "reject_rate_over_100" {
  command = plan
  variables {
    cloudwatch_alarm_error_rate_threshold = 101
  }
  expect_failures = [var.cloudwatch_alarm_error_rate_threshold]
}

run "reject_subminute_period" {
  command = plan
  variables {
    cloudwatch_alarm_period = 30
  }
  expect_failures = [var.cloudwatch_alarm_period]
}

run "reject_fractional_evaluations" {
  command = plan
  variables {
    cloudwatch_alarm_evaluation_periods = 1.5
  }
  expect_failures = [var.cloudwatch_alarm_evaluation_periods]
}

run "reject_multi_day_window" {
  command = plan
  variables {
    cloudwatch_alarm_evaluation_periods = 1000
  }
  expect_failures = [var.cloudwatch_alarm_evaluation_periods]
}

run "reject_regional_cross_region_metrics" {
  command = plan
  variables {
    cloudwatch_alarm_additional_regions = ["us-west-2"]
  }
  expect_failures = [var.cloudwatch_alarm_additional_regions]
}
