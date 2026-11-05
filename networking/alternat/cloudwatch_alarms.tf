################################################################################
# Lambda error-rate alarms
################################################################################

locals {
  # Every Lambda alterNAT runs: the autoscaling hook, and one connectivity
  # tester per NAT instance.
  alarmed_function_names = var.cloudwatch_alarms_creation_enabled ? toset(concat(
    [local.autoscaling_hook_function_name],
    [for az in local.nat_azs : "${local.connectivity_tester_function_name}-${az}"],
  )) : toset([])
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  for_each = local.alarmed_function_names

  alarm_name          = "lambda-${each.key}-error-rate"
  alarm_description   = "Lambda invocation error rate (%) for alterNAT function ${each.key}. A failing function can leave traffic on a broken NAT instance; check its logs."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  threshold           = var.cloudwatch_alarm_error_rate_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.cloudwatch_alarm_actions
  ok_actions          = var.cloudwatch_ok_actions
  tags                = local.tags

  metric_query {
    id          = "error_rate"
    expression  = "IF(invocations > 0, 100 * errors / invocations, 0)"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id          = "errors"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      stat        = "Sum"
      period      = var.cloudwatch_alarm_period
      dimensions = {
        FunctionName = each.key
      }
    }
  }

  metric_query {
    id          = "invocations"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      stat        = "Sum"
      period      = var.cloudwatch_alarm_period
      dimensions = {
        FunctionName = each.key
      }
    }
  }

  depends_on = [module.alternat]
}
