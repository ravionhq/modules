################################################################################
# hosting/static_site - Default error-rate monitoring and configuration tests
################################################################################

mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.hosting_bucket_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.deploy_role_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# CloudFront distribution, KVS, CloudFront Functions, and the optional
# response-headers policy all run through the us_east_1 alias. Their resource
# overrides live here so apply-mode tests don't hit the real CloudFront API
# and so resource arns are deterministic.
mock_provider "aws" {
  alias = "us_east_1"

  # Mock providers do not derive computed regions from provider configuration.
  # Set this only on the alias so the assertion detects incorrect provider wiring.
  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      region = "us-east-1"
    }
  }

  override_resource {
    target = aws_cloudfront_function.rewrite
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-rewrite"
    }
  }

  override_resource {
    target = aws_cloudfront_function.cache_control
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-cache-control"
    }
  }

  override_resource {
    target = aws_cloudfront_key_value_store.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:key-value-store/12345678-1234-1234-1234-123456789012"
      id  = "12345678-1234-1234-1234-123456789012"
    }
  }

  override_resource {
    target = aws_cloudfront_response_headers_policy.this
    values = {
      id = "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  override_resource {
    target = aws_cloudfront_cache_policy.this
    values = {
      id = "module-cache-policy-11111111-2222-3333-4444-555555555555"
    }
  }

  # The delivery-source and delivery-destination resources validate their ARN
  # attributes at plan time, so mocked upstream ARNs must be well-formed.
  override_resource {
    target = module.cdn.aws_cloudfront_distribution.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE123"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_group.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/ravion-test-site"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_delivery_destination.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:ravion-test-site-access-logs-cw"
    }
  }
}

variables {
  name   = "test-site"
  region = "us-west-2"
}

run "default_distribution_alarm" {
  command = plan
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 1 && aws_cloudwatch_metric_alarm.error_rate["main"].metric_name == "5xxErrorRate" && aws_cloudwatch_metric_alarm.error_rate["main"].namespace == "AWS/CloudFront"
    error_message = "Create a CloudFront error-rate alarm by default."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["main"].dimensions.Region == "Global" && aws_cloudwatch_metric_alarm.error_rate["main"].region == "us-east-1" && aws_cloudwatch_metric_alarm.error_rate["main"].statistic == "Average"
    error_message = "Use global CloudFront metrics in us-east-1 even when hosting is in us-west-2."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["main"].threshold == 1 && aws_cloudwatch_metric_alarm.error_rate["main"].period == 300 && aws_cloudwatch_metric_alarm.error_rate["main"].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.error_rate["main"].treat_missing_data == "notBreaching"
    error_message = "Default to 1 percent in 5 minutes and ignore idle periods."
  }
}

run "multiple_distributions_and_actions" {
  command = apply
  variables {
    distributions                         = { main = {}, preview = {} }
    cloudwatch_alarm_error_rate_threshold = 2.5
    cloudwatch_alarm_period               = 60
    cloudwatch_alarm_evaluation_periods   = 3
    cloudwatch_alarm_actions              = ["arn:aws:sns:us-east-1:123456789012:alerts"]
    cloudwatch_ok_actions                 = ["arn:aws:sns:us-east-1:123456789012:recovery"]
  }
  assert {
    condition     = toset(keys(output.cloudwatch_alarm_arns)) == toset(["main", "preview"])
    error_message = "Every distribution needs its own alarm and output."
  }
  assert {
    condition     = alltrue([for key, alarm in aws_cloudwatch_metric_alarm.error_rate : alarm.dimensions.DistributionId == module.cdn.distribution_ids[key]])
    error_message = "Each alarm must target its own distribution ID."
  }
  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.error_rate : a.threshold == 2.5 && a.period == 60 && a.evaluation_periods == 3 && a.alarm_actions == toset(var.cloudwatch_alarm_actions) && a.ok_actions == toset(var.cloudwatch_ok_actions)])
    error_message = "Apply threshold, window, and notification overrides to every distribution."
  }
}

run "explicit_opt_out" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled = false
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 0 && length(output.cloudwatch_alarm_arns) == 0
    error_message = "Allow users to disable managed alarms."
  }
}

run "null_inputs_use_defaults" {
  command = plan
  variables {
    cloudwatch_alarms_creation_enabled    = null
    cloudwatch_alarm_error_rate_threshold = null
    cloudwatch_alarm_actions              = null
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 1 && aws_cloudwatch_metric_alarm.error_rate["main"].threshold == 1
    error_message = "Hidden/null inputs must preserve monitoring defaults."
  }
}

run "reject_zero_threshold" {
  command = plan
  variables {
    cloudwatch_alarm_error_rate_threshold = 0
  }
  expect_failures = [var.cloudwatch_alarm_error_rate_threshold]
}

run "reject_threshold_over_100" {
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

run "reject_fractional_evaluation_periods" {
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
