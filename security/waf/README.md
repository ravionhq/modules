# AWS WAF Module

Creates a WAFv2 web ACL for Application Load Balancers or CloudFront distributions, with rules aimed at automated abuse of sensitive paths such as sign-up, login and verification.

## Features

- AWS IP reputation list on every request
- Per-IP rate limit (429) across chosen path prefixes
- AWS anonymous IP list (VPNs, Tor, proxies, hosting providers) on those paths only
- Optional AWS Bot Control (common level) on its own path prefixes
- Count-only mode to watch the rules before they block
- `alb` target: a regional web ACL associated with each listed ALB
- `cloudfront` target: a global web ACL in us-east-1 for distributions to reference

## Usage

### Application Load Balancer

```hcl
module "waf" {
  source = "github.com/ravionhq/modules//security/waf"

  name     = "public-alb"
  target   = "alb"
  alb_arns = [module.alb.alb_arn]

  protected_paths   = ["/auth/signup", "/auth/verify-email"]
  rate_limit        = 100
  bot_control_paths = ["/auth/signup"]
}
```

### CloudFront distribution

CloudFront only accepts global web ACLs created in us-east-1, and a distribution names its web ACL itself, so the module associates nothing and exposes the ARN:

```hcl
module "waf" {
  source = "github.com/ravionhq/modules//security/waf"

  name            = "site-cdn"
  target          = "cloudfront"
  protected_paths = ["/signup"]
}

module "cdn" {
  source = "github.com/ravionhq/modules//cdn/cloudfront"
  # ...
  web_acl_id = module.waf.web_acl_arn
}
```

## Rules

| Priority | Rule | Applies to | Action |
| --- | --- | --- | --- |
| 10 | `aws-ip-reputation` (AWSManagedRulesAmazonIpReputationList) | Every request | Block |
| 20 | `protected-paths-rate-limit` | `protected_paths` | 429 once one IP exceeds `rate_limit` in `rate_limit_window_seconds` |
| 30 | `aws-anonymous-ip` (AWSManagedRulesAnonymousIpList) | `protected_paths` | Block |
| 40 | `aws-bot-control` (AWSManagedRulesBotControlRuleSet, common) | `bot_control_paths` | The managed group's actions |

Paths are prefixes matched against the lowercased URL path. Requests no rule matches are allowed. The anonymous IP list stays off every other path on purpose: CI systems, SDKs, agents and other machine callers usually run on hosting providers. When such callers use the protected paths too, set `anonymous_ip_block_hosting_providers = false` to count hosting-provider addresses while VPNs, Tor and proxies stay blocked. Bot Control is billed per inspected request.

`count_only = true` switches every rule to count. Each rule publishes CloudWatch metrics named `<name>-<rule>` and keeps sampled requests, so you can check what would have been blocked before turning it off.

## Advanced Terraform variables

These settings are not in the form. Set them in Advanced Terraform variables; their defaults change nothing.

| Variable | What it does |
| --- | --- |
| `ip_allow_list` / `ip_block_list` | IPv4 and IPv6 CIDRs always allowed (priority 1) or blocked (2). |
| `blocked_country_codes` | Two-letter country codes to block (3). |
| `custom_rules_json` + `custom_rules_capacity` | Any rules, in the AWS WAF API JSON format, in a rule group evaluated at priority 5. |
| `custom_rules_response_bodies` | Response bodies the custom rules can send, by key (`content`, `content_type`). A custom rule refers to one with `CustomResponseBodyKey`. |
| `managed_rule_groups` | More managed rule groups, each with its priority, optional path scope, count only and per-rule overrides. |
| `rule_action_overrides` | Per-rule actions in the module's own groups: `ip_reputation`, `anonymous_ip`, `bot_control`. |
| `rate_limit_aggregate_key` + `rate_limit_header_name` | Count the rate limit per `IP`, `FORWARDED_IP` or `HEADER`. |
| `rate_limit_response_body` + `rate_limit_response_content_type` | Body of the 429 response. |
| `bot_control_inspection_level` | `COMMON` or `TARGETED`. |
| `default_action` | `allow` or `block` requests no rule matches. |
| `rule_priorities` | Move the module's rules: `ip_allow`, `ip_block`, `geo_block`, `custom_rules`, `ip_reputation`, `rate_limit`, `anonymous_ip`, `bot_control`. |
| `logging_destination_arn` + `logging_redacted_fields` | Log every request to a CloudWatch Logs group, S3 bucket or Firehose stream. |

Every rule needs its own priority; the plan fails if two collide.

IP lists, countries and custom rules:

```yaml
advanced_terraform_variables:
  ip_allow_list: ["198.51.100.0/24", "2001:db8::/32"]
  ip_block_list: ["203.0.113.7/32"]
  blocked_country_codes: ["KP"]
  custom_rules_capacity: 50
  custom_rules_json: >-
    [{"Name": "block-admin", "Priority": 0, "Action": {"Block": {}},
      "Statement": {"ByteMatchStatement": {"SearchString": "/admin", "FieldToMatch": {"UriPath": {}},
        "PositionalConstraint": "STARTS_WITH", "TextTransformations": [{"Priority": 0, "Type": "LOWERCASE"}]}},
      "VisibilityConfig": {"SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "block-admin"}}]
```

A custom rule can answer with its own body. AWS only lets a rule group's rules use bodies defined on that group, so define them in `custom_rules_response_bodies` rather than `rate_limit_response_body`:

```yaml
advanced_terraform_variables:
  custom_rules_response_bodies:
    user-agent-required:
      content: '{"code":"USER_AGENT_REQUIRED","message":"Send a User-Agent header."}'
      content_type: APPLICATION_JSON
  custom_rules_capacity: 10
  custom_rules_json: >-
    [{"Name": "limit-no-user-agent", "Priority": 0,
      "Action": {"Block": {"CustomResponse": {"ResponseCode": 429, "CustomResponseBodyKey": "user-agent-required"}}},
      "Statement": {"RateBasedStatement": {"Limit": 10, "EvaluationWindowSec": 300, "AggregateKeyType": "IP",
        "ScopeDownStatement": {"NotStatement": {"Statement": {"SizeConstraintStatement": {"FieldToMatch": {"SingleHeader": {"Name": "user-agent"}},
          "ComparisonOperator": "GT", "Size": 0, "TextTransformations": [{"Priority": 0, "Type": "NONE"}]}}}}}},
      "VisibilityConfig": {"SampledRequestsEnabled": true, "CloudWatchMetricsEnabled": true, "MetricName": "limit-no-user-agent"}}]
```

`custom_rules_capacity` reserves web ACL capacity units for the rule group. Changing it replaces the group: the new one is created first, the web ACL switches to it, then the old one is deleted.

More managed rule groups and overrides:

```yaml
advanced_terraform_variables:
  managed_rule_groups:
    - name: AWSManagedRulesCommonRuleSet
      priority: 60
      rule_action_overrides:
        SizeRestrictions_BODY: count
    - name: AWSManagedRulesSQLiRuleSet
      priority: 70
      paths: ["/api/"]
      count_only: true
  rule_action_overrides:
    bot_control:
      CategoryHttpLibrary: count
```

Rate limit key, response and Bot Control level:

```yaml
advanced_terraform_variables:
  rate_limit_aggregate_key: FORWARDED_IP
  rate_limit_header_name: X-Forwarded-For
  rate_limit_response_body: '{"error":"too many requests"}'
  rate_limit_response_content_type: APPLICATION_JSON
  bot_control_inspection_level: TARGETED
```

Default action, priorities and logging:

```yaml
advanced_terraform_variables:
  default_action: block
  rule_priorities:
    rate_limit: 15
  logging_destination_arn: arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-site
  logging_redacted_fields:
    - type: header
      name: Authorization
```

The logging destination must already exist and its name must start with `aws-waf-logs-`; for CloudFront, a log group or Firehose stream must be in us-east-1. The module does not create it.

### Not covered

- The IP lists and country blocking match the connecting address. Behind a proxy or CDN in front of the ALB, put them on that layer's web ACL instead.
- CAPTCHA and challenge immunity times, token domains and request body inspection limits keep AWS's defaults.

## Requirements

| Name | Version |
| --- | --- |
| OpenTofu/Terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| name | Web ACL name and CloudWatch metric prefix. | `string` | n/a | yes |
| target | `alb` or `cloudfront`. | `string` | `"alb"` | no |
| region | Region of an `alb` web ACL (the load balancers' region). Ignored for `cloudfront`. | `string` | provider region | no |
| alb_arns | ALBs to associate. Only for `alb`. | `list(string)` | `[]` | no |
| count_only | Count rule matches instead of blocking them. | `bool` | `false` | no |
| ip_reputation_enabled | Block the AWS IP reputation list on every request. | `bool` | `true` | no |
| protected_paths | Path prefixes for the rate limit and the anonymous IP list. | `list(string)` | `[]` | no |
| rate_limit | Requests per IP per window on the protected paths. | `number` | `100` | no |
| rate_limit_window_seconds | 60, 120, 300 or 600. | `number` | `300` | no |
| anonymous_ip_enabled | Block anonymous IPs on the protected paths. | `bool` | `true` | no |
| anonymous_ip_block_hosting_providers | `false` counts hosting-provider addresses instead of blocking them, for agents, CI and SDKs that run in the cloud. | `bool` | `true` | no |
| bot_control_paths | Path prefixes inspected by Bot Control. | `list(string)` | `[]` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |

The advanced variables are listed under [Advanced Terraform variables](#advanced-terraform-variables).

## Outputs

| Name | Description |
| --- | --- |
| web_acl_arn | Web ACL ARN; for CloudFront, the distribution's `web_acl_id`. |
| web_acl_id | Web ACL ID. |
| web_acl_name | Web ACL name. |
| scope | `REGIONAL` or `CLOUDFRONT`. |
| region | Region of the web ACL (us-east-1 for CloudFront). |
| cloudwatch_metric_dimensions | AWS/WAFV2 metric dimensions: `web_acl` for totals across every rule, `rules` to split by rule. |
| capacity | Web ACL capacity units used (AWS allows 1,500 by default). |
| associated_alb_arns | Load balancers the web ACL is associated with. |
| ip_set_arns | IP sets created for `ip_allow_list` and `ip_block_list`, by key. |
| custom_rule_group_arn | Rule group holding `custom_rules_json` (null without custom rules). |
| logging_enabled | Whether the web ACL logs to `logging_destination_arn`. |
