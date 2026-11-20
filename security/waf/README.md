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

Paths are prefixes matched against the lowercased URL path. Requests no rule matches are allowed. The anonymous IP list stays off every other path on purpose: CI systems, SDKs and other machine callers usually run on hosting providers. Bot Control is billed per inspected request.

`count_only = true` switches every rule to count. Each rule publishes CloudWatch metrics named `<name>-<rule>` and keeps sampled requests, so you can check what would have been blocked before turning it off.

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
| bot_control_paths | Path prefixes inspected by Bot Control. | `list(string)` | `[]` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| web_acl_arn | Web ACL ARN; for CloudFront, the distribution's `web_acl_id`. |
| web_acl_id | Web ACL ID. |
| web_acl_name | Web ACL name. |
| scope | `REGIONAL` or `CLOUDFRONT`. |
| region | Region of the web ACL (us-east-1 for CloudFront). |
| capacity | Web ACL capacity units used (AWS allows 1,500 by default). |
| associated_alb_arns | Load balancers the web ACL is associated with. |
