################################################################################
# Web ACL
################################################################################

variable "name" {
  type        = string
  description = "Name of the web ACL, also the prefix of its CloudWatch metric names."

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,128}$", var.name))
    error_message = "The name must be 1-128 letters, digits, hyphens or underscores."
  }
}

variable "target" {
  type        = string
  description = "What the web ACL protects: alb (a regional web ACL associated with alb_arns) or cloudfront (a global web ACL in us-east-1 for distributions to reference)."
  default     = "alb"

  validation {
    condition     = contains(["alb", "cloudfront"], var.target)
    error_message = "The target must be alb or cloudfront."
  }
}

variable "region" {
  type        = string
  description = "Region of a regional (alb) web ACL; it must be the load balancers' region. Defaults to the provider's region. Ignored for cloudfront, which is always us-east-1."
  default     = null
}

variable "alb_arns" {
  type        = list(string)
  description = "Application Load Balancers to associate the web ACL with. Only for the alb target."
  default     = []

  validation {
    condition     = alltrue([for arn in var.alb_arns : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/", arn))])
    error_message = "Each alb_arns entry must be an Application Load Balancer ARN."
  }

  validation {
    condition     = var.target == "alb" || length(var.alb_arns) == 0
    error_message = "alb_arns only applies to the alb target. Pass the web_acl_arn output to the CloudFront distribution instead."
  }
}

variable "count_only" {
  type        = bool
  description = "Count requests that match the rules instead of blocking them, to watch the rules in CloudWatch before enforcing them."
  default     = false
}

################################################################################
# Rules
################################################################################

variable "ip_reputation_enabled" {
  type        = bool
  description = "Block addresses on the AWS IP reputation list (known bots and malicious sources) on every request."
  default     = true
}

variable "protected_paths" {
  type        = list(string)
  description = "URL path prefixes (for example /auth/signup) that get the per-IP rate limit and, when anonymous_ip_enabled, the AWS anonymous IP list. Empty creates neither rule."
  default     = []

  validation {
    condition     = alltrue([for path in var.protected_paths : can(regex("^/[A-Za-z0-9/_.~-]*$", path))])
    error_message = "Each protected_paths entry must start with / and contain only letters, digits, /, _, ., ~ and -."
  }
}

variable "rate_limit" {
  type        = number
  description = "Requests one IP may send to the protected paths within rate_limit_window_seconds before the web ACL answers 429."
  default     = 100

  validation {
    condition     = var.rate_limit >= 10 && var.rate_limit <= 2000000000 && floor(var.rate_limit) == var.rate_limit
    error_message = "The rate_limit must be a whole number between 10 and 2000000000."
  }
}

variable "rate_limit_window_seconds" {
  type        = number
  description = "Window, in seconds, over which rate_limit is counted."
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_limit_window_seconds)
    error_message = "The rate_limit_window_seconds must be 60, 120, 300 or 600."
  }
}

variable "anonymous_ip_enabled" {
  type        = bool
  description = "Block VPNs, Tor, proxies and hosting providers (AWS anonymous IP list) on the protected paths. It never applies to other paths, where CI systems and other machine callers on hosting providers would be blocked."
  default     = true
}

variable "anonymous_ip_block_hosting_providers" {
  type        = bool
  description = "Block hosting-provider addresses on the protected paths as part of the anonymous IP list. Set false to count them instead, so agents, CI systems and SDKs running in the cloud can still reach those paths while VPNs, Tor and proxies stay blocked."
  default     = true
}

variable "bot_control_paths" {
  type        = list(string)
  description = "URL path prefixes inspected by AWS Bot Control (common level). Bot Control is billed per inspected request, so keep this to a few paths such as sign-up. Empty disables it."
  default     = []

  validation {
    condition     = alltrue([for path in var.bot_control_paths : can(regex("^/[A-Za-z0-9/_.~-]*$", path))])
    error_message = "Each bot_control_paths entry must start with / and contain only letters, digits, /, _, ., ~ and -."
  }
}

################################################################################
# Tags
################################################################################

variable "tags" {
  type        = map(string)
  description = "Tags to add to the web ACL."
  default     = {}
}

################################################################################
# Advanced (Terraform variables only)
#
# Not form inputs: set them through advanced_terraform_variables. The defaults
# change nothing.
################################################################################

variable "default_action" {
  type        = string
  description = "Action for requests no rule matches: allow or block."
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "The default_action must be allow or block."
  }
}

variable "rule_priorities" {
  type        = map(number)
  description = "Priorities of the module's own rules, lower first. Keys: ip_allow (default 1), ip_block (2), geo_block (3), custom_rules (5), ip_reputation (10), rate_limit (20), anonymous_ip (30), bot_control (40). Unset keys keep their default."
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.rule_priorities) : contains(["ip_allow", "ip_block", "geo_block", "custom_rules", "ip_reputation", "rate_limit", "anonymous_ip", "bot_control"], key)])
    error_message = "rule_priorities keys must be ip_allow, ip_block, geo_block, custom_rules, ip_reputation, rate_limit, anonymous_ip or bot_control."
  }
}

variable "ip_allow_list" {
  type        = list(string)
  description = "IPv4 and IPv6 CIDRs always allowed, before any other rule (for example offices or monitoring). Empty creates no rule."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ip_allow_list : can(cidrhost(cidr, 0))])
    error_message = "Each ip_allow_list entry must be a CIDR such as 203.0.113.0/24 or 2001:db8::/32."
  }
}

variable "ip_block_list" {
  type        = list(string)
  description = "IPv4 and IPv6 CIDRs always blocked. Empty creates no rule."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ip_block_list : can(cidrhost(cidr, 0))])
    error_message = "Each ip_block_list entry must be a CIDR such as 203.0.113.0/24 or 2001:db8::/32."
  }
}

variable "blocked_country_codes" {
  type        = list(string)
  description = "Two-letter ISO 3166 country codes whose requests are blocked. Empty creates no rule."
  default     = []

  validation {
    condition     = alltrue([for code in var.blocked_country_codes : can(regex("^[A-Z]{2}$", code))])
    error_message = "Each blocked_country_codes entry must be an uppercase two-letter ISO 3166 code, such as KP."
  }
}

variable "custom_rules_json" {
  type        = string
  description = "Arbitrary rules as a JSON array in the AWS WAF API Rule format (Name, Priority, Statement, Action, VisibilityConfig). They go into a rule group the web ACL evaluates at the custom_rules priority, so any statement nesting works. Requires custom_rules_capacity."
  default     = null

  validation {
    # concat accepts any JSON array (rules of different shapes share no
    # element type) and rejects objects and scalars.
    condition     = var.custom_rules_json == null || can(concat(jsondecode(var.custom_rules_json), []))
    error_message = "custom_rules_json must be a JSON array of rules."
  }
}

variable "custom_rules_response_bodies" {
  type = map(object({
    content      = string
    content_type = optional(string, "APPLICATION_JSON")
  }))
  description = "Response bodies the custom rules can send, by key. A rule in custom_rules_json uses one with \"CustomResponse\": {\"ResponseCode\": 429, \"CustomResponseBodyKey\": \"<key>\"} in its Block action. AWS only lets a rule group's rules use bodies defined on that group, so the web ACL's rate_limit_response_body is not available to them. content_type is TEXT_PLAIN, TEXT_HTML or APPLICATION_JSON."
  default     = {}

  validation {
    condition = alltrue([for key, body in var.custom_rules_response_bodies :
      can(regex("^[A-Za-z0-9_-]{1,128}$", key)) &&
      length(body.content) >= 1 && length(body.content) <= 10240 &&
      contains(["TEXT_PLAIN", "TEXT_HTML", "APPLICATION_JSON"], body.content_type)
    ])
    error_message = "Each custom_rules_response_bodies key must be 1-128 letters, digits, _ or -, with 1-10240 characters of content and a content_type of TEXT_PLAIN, TEXT_HTML or APPLICATION_JSON."
  }
}

variable "custom_rules_capacity" {
  type        = number
  description = "Web ACL capacity units reserved for the custom rule group. Changing it replaces the group: the new one is created first and the old one deleted once the web ACL has switched."
  default     = null

  validation {
    condition     = var.custom_rules_capacity == null || (try(var.custom_rules_capacity >= 1 && var.custom_rules_capacity <= 5000 && floor(var.custom_rules_capacity) == var.custom_rules_capacity, false))
    error_message = "custom_rules_capacity must be a whole number between 1 and 5000."
  }
}

variable "managed_rule_groups" {
  type = list(object({
    name                  = string
    vendor_name           = optional(string, "AWS")
    version               = optional(string)
    priority              = number
    paths                 = optional(list(string), [])
    count_only            = optional(bool)
    rule_action_overrides = optional(map(string), {})
  }))
  description = "More managed rule groups, such as AWSManagedRulesCommonRuleSet, AWSManagedRulesKnownBadInputsRuleSet or AWSManagedRulesSQLiRuleSet. paths scopes a group to path prefixes; count_only defaults to the module's; rule_action_overrides maps rule names in the group to allow, block, count, captcha or challenge."
  default     = []

  validation {
    condition = alltrue([for group in var.managed_rule_groups :
      can(regex("^[A-Za-z0-9_-]{1,128}$", group.name)) &&
      alltrue([for path in group.paths : can(regex("^/[A-Za-z0-9/_.~-]*$", path))]) &&
      alltrue([for action in values(group.rule_action_overrides) : contains(["allow", "block", "count", "captcha", "challenge"], action)])
    ])
    error_message = "Each managed rule group needs a valid name, paths starting with / that contain only letters, digits, /, _, ., ~ and -, and rule_action_overrides of allow, block, count, captcha or challenge."
  }
}

variable "rule_action_overrides" {
  type        = map(map(string))
  description = "Per-rule action overrides on the module's managed groups. Keys: ip_reputation, anonymous_ip, bot_control. Values map rule names in the group (for example AnonymousIPList or CategoryHttpLibrary) to allow, block, count, captcha or challenge."
  default     = {}

  validation {
    condition = alltrue([for group, overrides in var.rule_action_overrides :
      contains(["ip_reputation", "anonymous_ip", "bot_control"], group) &&
      alltrue([for action in values(overrides) : contains(["allow", "block", "count", "captcha", "challenge"], action)])
    ])
    error_message = "rule_action_overrides keys must be ip_reputation, anonymous_ip or bot_control, with actions allow, block, count, captcha or challenge."
  }
}

variable "rate_limit_aggregate_key" {
  type        = string
  description = "What the rate limit counts per: IP (the connecting address), FORWARDED_IP (the first address in rate_limit_header_name, for traffic that reaches the ALB through a proxy or CDN) or HEADER (each value of rate_limit_header_name)."
  default     = "IP"

  validation {
    condition     = contains(["IP", "FORWARDED_IP", "HEADER"], var.rate_limit_aggregate_key)
    error_message = "The rate_limit_aggregate_key must be IP, FORWARDED_IP or HEADER."
  }
}

variable "rate_limit_header_name" {
  type        = string
  description = "Header read by the FORWARDED_IP and HEADER rate limit keys."
  default     = "X-Forwarded-For"
}

variable "rate_limit_response_body" {
  type        = string
  description = "Body of the 429 response the rate limit sends. Null sends AWS WAF's empty body."
  default     = null
}

variable "rate_limit_response_content_type" {
  type        = string
  description = "Content type of rate_limit_response_body: TEXT_PLAIN, TEXT_HTML or APPLICATION_JSON."
  default     = "APPLICATION_JSON"

  validation {
    condition     = contains(["TEXT_PLAIN", "TEXT_HTML", "APPLICATION_JSON"], var.rate_limit_response_content_type)
    error_message = "The rate_limit_response_content_type must be TEXT_PLAIN, TEXT_HTML or APPLICATION_JSON."
  }
}

variable "bot_control_inspection_level" {
  type        = string
  description = "Bot Control level: COMMON, or TARGETED for sophisticated bots (billed higher)."
  default     = "COMMON"

  validation {
    condition     = contains(["COMMON", "TARGETED"], var.bot_control_inspection_level)
    error_message = "The bot_control_inspection_level must be COMMON or TARGETED."
  }
}

variable "logging_destination_arn" {
  type        = string
  description = "Where the web ACL logs every request: a CloudWatch Logs log group, S3 bucket or Kinesis Data Firehose stream whose name starts with aws-waf-logs-. The destination must already exist; for CloudFront a log group or stream must be in us-east-1. Null turns logging off."
  default     = null

  validation {
    condition     = var.logging_destination_arn == null || can(regex("^arn:aws[a-z-]*:(logs|s3|firehose):[^ ]*aws-waf-logs-", var.logging_destination_arn))
    error_message = "logging_destination_arn must be a CloudWatch Logs, S3 or Firehose ARN whose name starts with aws-waf-logs-."
  }
}

variable "logging_redacted_fields" {
  type = list(object({
    type = string
    name = optional(string)
  }))
  description = "Request parts left out of the logs: type is header (with name), query_string, uri_path or method."
  default     = []

  validation {
    condition     = alltrue([for field in var.logging_redacted_fields : contains(["header", "query_string", "uri_path", "method"], field.type) && (field.type != "header" || field.name != null)])
    error_message = "Each logging_redacted_fields entry needs type header (with a name), query_string, uri_path or method."
  }
}
