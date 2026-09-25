locals {
  # Edge replicas emit metrics in their execution Regions with the origin prefix.
  alarm_regions       = var.cloudwatch_alarms_creation_enabled ? toset(concat([local.region], var.cloudwatch_alarm_additional_regions)) : toset([])
  alarm_function_name = var.lambda_at_edge_enabled ? "${local.region}.${var.name}" : var.name
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  for_each = local.alarm_regions

  region              = each.key
  alarm_name          = "lambda-${var.name}-error-rate"
  alarm_description   = "Lambda invocation error rate (%) for ${var.name} in ${each.key}. Check function logs and recent deployments."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  threshold           = var.cloudwatch_alarm_error_rate_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = lookup(var.cloudwatch_alarm_actions_by_region, each.key, var.cloudwatch_alarm_actions)
  ok_actions          = lookup(var.cloudwatch_ok_actions_by_region, each.key, var.cloudwatch_ok_actions)
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
        FunctionName = local.alarm_function_name
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
        FunctionName = local.alarm_function_name
      }
    }
  }
}
