# WAF module tests for the alb target — run from module root: tofu test
#
# A regional web ACL in the load balancers' region, associated with each ALB.
# The anonymous IP list and the rate limit apply only to the protected paths,
# so machine callers from hosting providers keep reaching the rest of the ALB;
# Bot Control is billed per request and only covers its own paths.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-west-2:123456789012:regional/webacl/test/12345678-1234-1234-1234-123456789012" }
  }
}

variables {
  name     = "test-waf"
  target   = "alb"
  alb_arns = ["arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/public/0123456789abcdef"]
}

run "defaults_block_the_ip_reputation_list_only" {
  command = apply

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL" && aws_wafv2_web_acl.this.region == "us-west-2" && output.scope == "REGIONAL"
    error_message = "An alb web ACL must be regional, in the provider's region."
  }
  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.name] == ["aws-ip-reputation"]
    error_message = "Without protected or bot control paths the ACL must only carry the IP reputation rule."
  }
  assert {
    condition     = length(one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-ip-reputation"]).override_action[0].none) == 1
    error_message = "The IP reputation rule must enforce the managed group's own actions."
  }
  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].allow) == 1
    error_message = "Requests no rule matches must be allowed."
  }
}

run "associates_every_alb_in_the_acl_region" {
  command = apply

  variables {
    region = "eu-central-1"
    alb_arns = [
      "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/app/one/0123456789abcdef",
      "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/app/two/fedcba9876543210",
    ]
  }

  assert {
    condition     = output.associated_alb_arns == sort(var.alb_arns)
    error_message = "Each ALB must be associated with the web ACL."
  }
  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl_association.alb : a.region == "eu-central-1" && a.web_acl_arn == aws_wafv2_web_acl.this.arn])
    error_message = "Associations must point at this web ACL, in its region."
  }
  assert {
    condition     = aws_wafv2_web_acl.this.region == "eu-central-1"
    error_message = "region must place a regional web ACL."
  }
}

run "protected_paths_get_rate_limit_and_anonymous_ip_rules" {
  command = apply

  variables {
    protected_paths           = ["/auth/signup", "/auth/verify-email", "/v1.0/Login"]
    rate_limit                = 50
    rate_limit_window_seconds = 600
  }

  assert {
    condition     = [for r in sort([for r in aws_wafv2_web_acl.this.rule : format("%03d %s", r.priority, r.name)]) : split(" ", r)[1]] == ["aws-ip-reputation", "protected-paths-rate-limit", "aws-anonymous-ip"]
    error_message = "Protected paths must add the rate limit and anonymous IP rules after IP reputation."
  }
  assert {
    condition = alltrue([for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit == 50 &&
      r.statement[0].rate_based_statement[0].evaluation_window_sec == 600 &&
    r.statement[0].rate_based_statement[0].aggregate_key_type == "IP" if r.name == "protected-paths-rate-limit"])
    error_message = "The rate limit must count each IP against rate_limit over the configured window."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).statement[0].rate_based_statement[0].scope_down_statement[0].regex_match_statement[0].regex_string == "^(/auth/signup|/auth/verify-email|/v1\\.0/login)"
    error_message = "The rate limit must be scoped to the protected path prefixes, lowercased with dots escaped."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "protected-paths-rate-limit"]).action[0].block[0].custom_response[0].response_code == 429
    error_message = "Requests over the rate limit must be answered with 429."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-anonymous-ip"]).statement[0].managed_rule_group_statement[0].scope_down_statement[0].regex_match_statement[0].regex_string == "^(/auth/signup|/auth/verify-email|/v1\\.0/login)"
    error_message = "The anonymous IP list must only apply to the protected paths, never site-wide."
  }
}

run "anonymous_ip_list_can_be_left_off" {
  command = apply

  variables {
    protected_paths       = ["/auth/signup"]
    anonymous_ip_enabled  = false
    ip_reputation_enabled = false
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.name] == ["protected-paths-rate-limit"]
    error_message = "Turning off IP reputation and the anonymous IP list must leave only the rate limit."
  }
}

run "bot_control_is_scoped_to_its_paths" {
  command = apply

  variables {
    bot_control_paths = ["/auth/signup"]
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-bot-control"]).statement[0].managed_rule_group_statement[0].managed_rule_group_configs[0].aws_managed_rules_bot_control_rule_set[0].inspection_level == "COMMON"
    error_message = "Bot Control must use the common inspection level."
  }
  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r if r.name == "aws-bot-control"]).statement[0].managed_rule_group_statement[0].scope_down_statement[0].regex_match_statement[0].regex_string == "^(/auth/signup)"
    error_message = "Bot Control must only inspect its own paths."
  }
}

run "count_only_counts_every_rule" {
  command = apply

  variables {
    count_only        = true
    protected_paths   = ["/auth/"]
    bot_control_paths = ["/auth/signup"]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 4
    error_message = "All four rules must exist in count-only mode."
  }
  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.name == "protected-paths-rate-limit" ? length(r.action[0].count) == 1 && length(r.action[0].block) == 0 : length(r.override_action[0].count) == 1 && length(r.override_action[0].none) == 0])
    error_message = "Count-only mode must count every rule's matches instead of blocking them."
  }
}

run "rejects_regex_characters_in_paths" {
  command = plan

  variables {
    protected_paths = ["/auth/(signup|login)"]
  }

  expect_failures = [var.protected_paths]
}

run "rejects_non_alb_arns" {
  command = plan

  variables {
    alb_arns = ["arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/net/nlb/0123456789abcdef"]
  }

  expect_failures = [var.alb_arns]
}
