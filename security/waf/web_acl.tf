################################################################################
# Web ACL
#
# Rules, in default priority order (rule_priorities moves them):
#
#    1. ip_allow_list: allow.
#    2. ip_block_list: block.
#    3. blocked_country_codes: block.
#    5. custom_rules_json, as a rule group.
#   10. AWS IP reputation list, on every request.
#   20. Per-IP rate limit across the protected paths (429 when exceeded).
#   30. AWS anonymous IP list (VPNs, Tor, hosting providers), on the protected
#       paths only.
#   40. AWS Bot Control, on the bot control paths only.
#   managed_rule_groups at their own priorities.
#
# Count-only mode switches every rule but the IP allow list to count.
################################################################################

resource "aws_wafv2_web_acl" "this" {
  region = local.region

  name        = var.name
  description = "Managed by Ravion: IP reputation, path rate limits, anonymous IPs and bot control."
  scope       = local.scope
  tags        = local.tags

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  dynamic "custom_response_body" {
    for_each = var.rate_limit_response_body == null ? [] : [var.rate_limit_response_body]

    content {
      key          = local.rate_limit_response_body_key
      content      = custom_response_body.value
      content_type = var.rate_limit_response_content_type
    }
  }

  ##############################################################################
  # IP allow and block lists, country blocking
  ##############################################################################

  dynamic "rule" {
    for_each = length(local.ip_allow_set_arns) > 0 ? [local.ip_allow_set_arns] : []

    content {
      name     = "ip-allow-list"
      priority = local.priorities.ip_allow

      action {
        allow {}
      }

      statement {
        dynamic "ip_set_reference_statement" {
          for_each = length(rule.value) == 1 ? rule.value : []
          content {
            arn = ip_set_reference_statement.value
          }
        }
        dynamic "or_statement" {
          for_each = length(rule.value) > 1 ? [rule.value] : []
          content {
            dynamic "statement" {
              for_each = or_statement.value
              content {
                ip_set_reference_statement {
                  arn = statement.value
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-ip-allow-list"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = length(local.ip_block_set_arns) > 0 ? [local.ip_block_set_arns] : []

    content {
      name     = "ip-block-list"
      priority = local.priorities.ip_block

      action {
        dynamic "block" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        dynamic "ip_set_reference_statement" {
          for_each = length(rule.value) == 1 ? rule.value : []
          content {
            arn = ip_set_reference_statement.value
          }
        }
        dynamic "or_statement" {
          for_each = length(rule.value) > 1 ? [rule.value] : []
          content {
            dynamic "statement" {
              for_each = or_statement.value
              content {
                ip_set_reference_statement {
                  arn = statement.value
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-ip-block-list"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = length(var.blocked_country_codes) > 0 ? [var.blocked_country_codes] : []

    content {
      name     = "geo-block"
      priority = local.priorities.geo_block

      action {
        dynamic "block" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        geo_match_statement {
          country_codes = rule.value
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # Custom rules (rule_group.tf)
  ##############################################################################

  dynamic "rule" {
    for_each = aws_wafv2_rule_group.custom

    content {
      name     = "custom-rules"
      priority = local.priorities.custom_rules

      override_action {
        dynamic "none" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        rule_group_reference_statement {
          arn = rule.value.arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-custom-rules"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # AWS IP reputation list
  ##############################################################################

  dynamic "rule" {
    for_each = var.ip_reputation_enabled ? [lookup(var.rule_action_overrides, "ip_reputation", {})] : []

    content {
      name     = "aws-ip-reputation"
      priority = local.priorities.ip_reputation

      override_action {
        dynamic "none" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = rule.value

            content {
              name = rule_action_override.key

              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # Per-IP rate limit on the protected paths
  ##############################################################################

  dynamic "rule" {
    for_each = local.protected_paths_regex == null ? [] : [local.protected_paths_regex]

    content {
      name     = "protected-paths-rate-limit"
      priority = local.priorities.rate_limit

      action {
        dynamic "block" {
          for_each = var.count_only ? [] : [1]
          content {
            custom_response {
              response_code            = 429
              custom_response_body_key = var.rate_limit_response_body == null ? null : local.rate_limit_response_body_key
            }
          }
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit                 = var.rate_limit
          evaluation_window_sec = var.rate_limit_window_seconds
          aggregate_key_type    = var.rate_limit_aggregate_key == "HEADER" ? "CUSTOM_KEYS" : var.rate_limit_aggregate_key

          dynamic "forwarded_ip_config" {
            for_each = var.rate_limit_aggregate_key == "FORWARDED_IP" ? [var.rate_limit_header_name] : []
            content {
              header_name       = forwarded_ip_config.value
              fallback_behavior = "MATCH"
            }
          }

          dynamic "custom_key" {
            for_each = var.rate_limit_aggregate_key == "HEADER" ? [var.rate_limit_header_name] : []
            content {
              header {
                name = custom_key.value
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }

          scope_down_statement {
            regex_match_statement {
              regex_string = rule.value

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # AWS anonymous IP list on the protected paths
  ##############################################################################

  dynamic "rule" {
    for_each = var.anonymous_ip_enabled && local.protected_paths_regex != null ? [local.protected_paths_regex] : []

    content {
      name     = "aws-anonymous-ip"
      priority = local.priorities.anonymous_ip

      override_action {
        dynamic "none" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAnonymousIpList"
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = local.anonymous_ip_overrides

            content {
              name = rule_action_override.key

              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }

          scope_down_statement {
            regex_match_statement {
              regex_string = rule.value

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-anonymous-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # AWS Bot Control on the bot control paths
  ##############################################################################

  dynamic "rule" {
    for_each = local.bot_control_paths_regex == null ? [] : [local.bot_control_paths_regex]

    content {
      name     = "aws-bot-control"
      priority = local.priorities.bot_control

      override_action {
        dynamic "none" {
          for_each = var.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = var.bot_control_inspection_level
            }
          }

          dynamic "rule_action_override" {
            for_each = lookup(var.rule_action_overrides, "bot_control", {})

            content {
              name = rule_action_override.key

              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }

          scope_down_statement {
            regex_match_statement {
              regex_string = rule.value

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  ##############################################################################
  # More managed rule groups
  ##############################################################################

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = "managed-${lower(rule.value.name)}"
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
          version     = rule.value.version

          dynamic "rule_action_override" {
            for_each = rule.value.rule_action_overrides

            content {
              name = rule_action_override.key

              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }

          dynamic "scope_down_statement" {
            for_each = rule.value.paths_regex == null ? [] : [rule.value.paths_regex]

            content {
              regex_match_statement {
                regex_string = scope_down_statement.value

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-${lower(rule.value.name)}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.metric_prefix
    sampled_requests_enabled   = true
  }

  lifecycle {
    precondition {
      condition     = length(distinct(local.used_priorities)) == length(local.used_priorities)
      error_message = "Every rule needs its own priority. Check rule_priorities and the priorities in managed_rule_groups."
    }
  }
}
