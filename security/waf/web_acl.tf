################################################################################
# Web ACL
#
# Rules, in priority order:
#
#   10. AWS IP reputation list, on every request.
#   20. Per-IP rate limit across the protected paths (429 when exceeded).
#   30. AWS anonymous IP list (VPNs, Tor, hosting providers), on the protected
#       paths only.
#   40. AWS Bot Control (common inspection), on the bot control paths only.
#
# Count-only mode switches every rule to count.
################################################################################

resource "aws_wafv2_web_acl" "this" {
  region = local.region

  name        = var.name
  description = "Managed by Ravion: IP reputation, path rate limits, anonymous IPs and bot control."
  scope       = local.scope
  tags        = local.tags

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = var.ip_reputation_enabled ? [1] : []

    content {
      name     = "aws-ip-reputation"
      priority = 10

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
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.metric_prefix}-ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.protected_paths_regex == null ? [] : [local.protected_paths_regex]

    content {
      name     = "protected-paths-rate-limit"
      priority = 20

      action {
        dynamic "block" {
          for_each = var.count_only ? [] : [1]
          content {
            custom_response {
              response_code = 429
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
          aggregate_key_type    = "IP"

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

  dynamic "rule" {
    for_each = var.anonymous_ip_enabled && local.protected_paths_regex != null ? [local.protected_paths_regex] : []

    content {
      name     = "aws-anonymous-ip"
      priority = 30

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

  dynamic "rule" {
    for_each = local.bot_control_paths_regex == null ? [] : [local.bot_control_paths_regex]

    content {
      name     = "aws-bot-control"
      priority = 40

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
              inspection_level = "COMMON"
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

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.metric_prefix
    sampled_requests_enabled   = true
  }
}
