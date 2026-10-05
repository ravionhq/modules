################################################################################
# Event Source Mappings
################################################################################

resource "aws_lambda_event_source_mapping" "this" {
  for_each = local.event_source_mappings_map

  event_source_arn = each.value.event_source_arn
  function_name    = aws_lambda_alias.this["live"].arn

  enabled                            = try(each.value.enabled, true)
  batch_size                         = try(each.value.batch_size, null)
  maximum_batching_window_in_seconds = try(each.value.maximum_batching_window_in_seconds, null)
  starting_position                  = try(each.value.starting_position, null)
  starting_position_timestamp        = try(each.value.starting_position_timestamp, null)
  parallelization_factor             = try(each.value.parallelization_factor, null)
  maximum_record_age_in_seconds      = try(each.value.maximum_record_age_in_seconds, null)
  bisect_batch_on_function_error     = try(each.value.bisect_batch_on_function_error, null)
  maximum_retry_attempts             = try(each.value.maximum_retry_attempts, null)
  tumbling_window_in_seconds         = try(each.value.tumbling_window_in_seconds, null)
  function_response_types            = try(each.value.function_response_types, null)

  dynamic "source_access_configuration" {
    for_each = try(each.value.source_access_configurations, [])
    content {
      type = source_access_configuration.value.type
      uri  = source_access_configuration.value.uri
    }
  }

  dynamic "filter_criteria" {
    for_each = length(try(each.value.filter_criteria, [])) > 0 ? [1] : []
    content {
      dynamic "filter" {
        for_each = try(each.value.filter_criteria, [])
        content {
          pattern = filter.value
        }
      }
    }
  }

  dynamic "scaling_config" {
    for_each = try(each.value.scaling_config_maximum_concurrency, null) != null ? [1] : []
    content {
      maximum_concurrency = each.value.scaling_config_maximum_concurrency
    }
  }

  dynamic "destination_config" {
    for_each = try(each.value.destination_config_on_failure_arn, null) != null ? [1] : []
    content {
      dynamic "on_failure" {
        for_each = try(each.value.destination_config_on_failure_arn, null) != null ? [1] : []
        content {
          destination_arn = each.value.destination_config_on_failure_arn
        }
      }
    }
  }
}
