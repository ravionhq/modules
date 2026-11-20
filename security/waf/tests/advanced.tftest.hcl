# Advanced Terraform variables on the alb target — run from module root:
# tofu test. These are not form inputs; they reach the module through
# advanced_terraform_variables, and their defaults change nothing.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-west-2:123456789012:regional/webacl/test/12345678-1234-1234-1234-123456789012" }
  }
  mock_resource "aws_wafv2_ip_set" {
    defaults = { arn = "arn:aws:wafv2:us-west-2:123456789012:regional/ipset/test/12345678-1234-1234-1234-123456789012" }
  }
  mock_resource "aws_wafv2_rule_group" {
    defaults = { arn = "arn:aws:wafv2:us-west-2:123456789012:regional/rulegroup/test/12345678-1234-1234-1234-123456789012" }
  }
}

variables {
  name            = "test-waf"
  target          = "alb"
  alb_arns        = ["arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/public/0123456789abcdef"]
  protected_paths = ["/auth/signup"]
}

run "default_action_can_block" {
  command = apply

  variables {
    default_action = "block"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].block) == 1 && length(aws_wafv2_web_acl.this.default_action[0].allow) == 0
    error_message = "default_action = block must block requests no rule matches."
  }
}

run "rule_priorities_move_the_module_rules" {
  command = apply

  variables {
    rule_priorities = { ip_reputation = 50, rate_limit = 5 }
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "aws-ip-reputation"]) == 50 && one([for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "protected-paths-rate-limit"]) == 5
    error_message = "rule_priorities must set the priorities of the module's rules."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "aws-anonymous-ip"]) == 30
    error_message = "Rules missing from rule_priorities must keep their default priority."
  }
}

run "duplicate_priorities_are_refused" {
  command = plan

  variables {
    rule_priorities = { rate_limit = 10 }
  }

  expect_failures = [aws_wafv2_web_acl.this]
}

run "ip_lists_create_ip_sets_and_rules" {
  command = apply

  variables {
    ip_allow_list = ["198.51.100.0/24", "2001:db8::/32"]
    ip_block_list = ["203.0.113.7/32"]
  }

  assert {
    condition     = join(",", sort(keys(aws_wafv2_ip_set.this))) == "allow-ipv4,allow-ipv6,block-ipv4"
    error_message = "Each address family of each list must get its own IP set."
  }
  assert {
    condition     = aws_wafv2_ip_set.this["allow-ipv6"].ip_address_version == "IPV6" && tolist(aws_wafv2_ip_set.this["allow-ipv6"].addresses) == tolist(["2001:db8::/32"]) && aws_wafv2_ip_set.this["allow-ipv4"].scope == "REGIONAL" && aws_wafv2_ip_set.this["allow-ipv4"].region == "us-west-2"
    error_message = "IP sets must hold one address family, in the web ACL's scope and region."
  }
  assert {
    condition     = length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-allow-list"]).action[0].allow) == 1 && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-allow-list"]).statement[0].or_statement[0].statement) == 2
    error_message = "The allow list must allow either address family."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-block-list"]).priority == 2 && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-block-list"]).statement[0].ip_set_reference_statement) == 1 && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-block-list"]).action[0].block) == 1
    error_message = "A single-family block list must block with one IP set reference."
  }
  assert {
    condition     = output.ip_set_arns["block-ipv4"] == aws_wafv2_ip_set.this["block-ipv4"].arn
    error_message = "IP set ARNs must be an output."
  }
}

run "count_only_counts_the_block_list_but_keeps_the_allow_list" {
  command = apply

  variables {
    count_only    = true
    ip_allow_list = ["198.51.100.0/24"]
    ip_block_list = ["203.0.113.7/32"]
  }

  assert {
    condition     = length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-block-list"]).action[0].count) == 1 && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "ip-allow-list"]).action[0].allow) == 1
    error_message = "Count-only must count the block list and leave the allow list allowing."
  }
}

run "countries_can_be_blocked" {
  command = apply

  variables {
    blocked_country_codes = ["KP", "IR"]
  }

  assert {
    condition     = tolist(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "geo-block"]).statement[0].geo_match_statement[0].country_codes) == tolist(["KP", "IR"])
    error_message = "blocked_country_codes must become a geo match rule."
  }
}

run "custom_rules_go_into_a_rule_group" {
  command = apply

  variables {
    custom_rules_capacity = 50
    custom_rules_json = jsonencode([{
      Name     = "block-admin-from-outside"
      Priority = 0
      Action   = { Block = {} }
      Statement = {
        ByteMatchStatement = {
          SearchString         = "/admin"
          FieldToMatch         = { UriPath = {} }
          PositionalConstraint = "STARTS_WITH"
          TextTransformations  = [{ Priority = 0, Type = "LOWERCASE" }]
        }
      }
      VisibilityConfig = { SampledRequestsEnabled = true, CloudWatchMetricsEnabled = true, MetricName = "admin" }
    }])
  }

  assert {
    condition     = aws_wafv2_rule_group.custom[0].capacity == 50 && aws_wafv2_rule_group.custom[0].scope == "REGIONAL" && jsondecode(aws_wafv2_rule_group.custom[0].rules_json)[0].Name == "block-admin-from-outside"
    error_message = "custom_rules_json must become a rule group with the given capacity."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "custom-rules"]).statement[0].rule_group_reference_statement[0].arn == aws_wafv2_rule_group.custom[0].arn && one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "custom-rules"]).priority == 5
    error_message = "The web ACL must evaluate the custom rule group at the custom_rules priority."
  }
  assert {
    condition     = output.custom_rule_group_arn == aws_wafv2_rule_group.custom[0].arn
    error_message = "The custom rule group ARN must be an output."
  }
}

run "custom_rules_need_a_capacity" {
  command = plan

  variables {
    custom_rules_json = "[]"
  }

  expect_failures = [aws_wafv2_rule_group.custom]
}

run "more_managed_rule_groups" {
  command = apply

  variables {
    managed_rule_groups = [
      {
        name                  = "AWSManagedRulesCommonRuleSet"
        priority              = 60
        rule_action_overrides = { SizeRestrictions_BODY = "count" }
      },
      {
        name       = "AWSManagedRulesSQLiRuleSet"
        priority   = 70
        paths      = ["/api/"]
        count_only = true
      },
    ]
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).priority == 60 && one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).statement[0].managed_rule_group_statement[0].vendor_name == "AWS"
    error_message = "Each managed group must be a rule at its priority, from AWS by default."
  }
  assert {
    condition     = one(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).statement[0].managed_rule_group_statement[0].rule_action_override).name == "SizeRestrictions_BODY" && length(one(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).statement[0].managed_rule_group_statement[0].rule_action_override).action_to_use[0].count) == 1
    error_message = "rule_action_overrides must override single rules in the group."
  }
  assert {
    condition     = length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).statement[0].managed_rule_group_statement[0].scope_down_statement) == 0 && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulescommonruleset"]).override_action[0].none) == 1
    error_message = "A group without paths must apply to every request and enforce its actions."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulessqliruleset"]).statement[0].managed_rule_group_statement[0].scope_down_statement[0].regex_match_statement[0].regex_string == "^(/api/)" && length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulessqliruleset"]).override_action[0].count) == 1
    error_message = "paths must scope a group down and count_only must count it."
  }
}

run "managed_groups_follow_module_count_only" {
  command = apply

  variables {
    count_only          = true
    managed_rule_groups = [{ name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 60 }]
  }

  assert {
    condition     = length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "managed-awsmanagedrulesknownbadinputsruleset"]).override_action[0].count) == 1
    error_message = "A managed group without count_only must follow the module's count_only."
  }
}

run "overrides_on_the_built_in_groups" {
  command = apply

  variables {
    bot_control_paths                    = ["/auth/signup"]
    anonymous_ip_block_hosting_providers = false
    rule_action_overrides = {
      ip_reputation = { AWSManagedIPDDoSList = "count" }
      anonymous_ip  = { AnonymousIPList = "challenge" }
      bot_control   = { CategoryHttpLibrary = "count" }
    }
  }

  assert {
    condition     = one(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-ip-reputation"]).statement[0].managed_rule_group_statement[0].rule_action_override).name == "AWSManagedIPDDoSList"
    error_message = "ip_reputation overrides must reach the IP reputation group."
  }
  assert {
    condition     = join(",", sort([for o in one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-anonymous-ip"]).statement[0].managed_rule_group_statement[0].rule_action_override : o.name])) == "AnonymousIPList,HostingProviderIPList"
    error_message = "anonymous_ip overrides must add to the hosting-provider override."
  }
  assert {
    condition     = length(one([for o in one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-anonymous-ip"]).statement[0].managed_rule_group_statement[0].rule_action_override : o if o.name == "AnonymousIPList"]).action_to_use[0].challenge) == 1
    error_message = "Overrides must use the given action."
  }
  assert {
    condition     = one(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-bot-control"]).statement[0].managed_rule_group_statement[0].rule_action_override).name == "CategoryHttpLibrary"
    error_message = "bot_control overrides must reach the Bot Control group."
  }
}

run "rate_limit_can_count_a_forwarded_ip" {
  command = apply

  variables {
    rate_limit_aggregate_key = "FORWARDED_IP"
    rate_limit_header_name   = "CloudFront-Viewer-Address"
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).statement[0].rate_based_statement[0].aggregate_key_type == "FORWARDED_IP" && one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).statement[0].rate_based_statement[0].forwarded_ip_config[0].header_name == "CloudFront-Viewer-Address"
    error_message = "FORWARDED_IP must count the address in the given header."
  }
}

run "rate_limit_can_count_a_header_and_send_a_body" {
  command = apply

  variables {
    rate_limit_aggregate_key         = "HEADER"
    rate_limit_header_name           = "X-Api-Key"
    rate_limit_response_body         = "{\"error\":\"slow down\"}"
    rate_limit_response_content_type = "APPLICATION_JSON"
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).statement[0].rate_based_statement[0].aggregate_key_type == "CUSTOM_KEYS" && one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).statement[0].rate_based_statement[0].custom_key[0].header[0].name == "X-Api-Key"
    error_message = "HEADER must count each value of the given header."
  }
  assert {
    condition     = one([for b in aws_wafv2_web_acl.this.custom_response_body : b if b.key == "rate-limited"]).content == "{\"error\":\"slow down\"}" && one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).action[0].block[0].custom_response[0].custom_response_body_key == "rate-limited"
    error_message = "The 429 must send rate_limit_response_body."
  }
}

run "bot_control_can_be_targeted" {
  command = apply

  variables {
    bot_control_paths            = ["/auth/signup"]
    bot_control_inspection_level = "TARGETED"
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-bot-control"]).statement[0].managed_rule_group_statement[0].managed_rule_group_configs[0].aws_managed_rules_bot_control_rule_set[0].inspection_level == "TARGETED"
    error_message = "bot_control_inspection_level must set the Bot Control level."
  }
}

run "logging_with_redacted_fields" {
  command = apply

  variables {
    logging_destination_arn = "arn:aws:logs:us-west-2:123456789012:log-group:aws-waf-logs-test"
    logging_redacted_fields = [{ type = "header", name = "Authorization" }, { type = "query_string" }]
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this[0].resource_arn == aws_wafv2_web_acl.this.arn && tolist(aws_wafv2_web_acl_logging_configuration.this[0].log_destination_configs) == tolist(["arn:aws:logs:us-west-2:123456789012:log-group:aws-waf-logs-test"]) && aws_wafv2_web_acl_logging_configuration.this[0].region == "us-west-2"
    error_message = "Logging must send the web ACL's logs to the destination, in the web ACL's region."
  }
  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields) == 2 && output.logging_enabled
    error_message = "Each redacted field must be left out of the logs."
  }
}

run "logging_is_off_by_default" {
  command = apply

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 0 && !output.logging_enabled && length(aws_wafv2_ip_set.this) == 0 && length(aws_wafv2_rule_group.custom) == 0
    error_message = "The advanced variables' defaults must create nothing."
  }
}

run "rejects_invalid_advanced_values" {
  command = plan

  variables {
    ip_block_list           = ["not-a-cidr"]
    blocked_country_codes   = ["korea"]
    logging_destination_arn = "arn:aws:logs:us-west-2:123456789012:log-group:my-logs"
    default_action          = "deny"
  }

  expect_failures = [var.ip_block_list, var.blocked_country_codes, var.logging_destination_arn, var.default_action]
}
