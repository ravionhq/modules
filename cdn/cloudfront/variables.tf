################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 63
    error_message = "The name must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name))
    error_message = "The name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "distributions" {
  type = map(object({
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    comment             = optional(string)
    enabled             = optional(bool, true)
  }))
  description = "A map of CloudFront distributions to create. Each key is a distribution identifier. All distributions share origins, cache behaviors, and other settings."

  validation {
    condition     = length(var.distributions) > 0
    error_message = "At least one distribution must be specified."
  }

  validation {
    condition     = alltrue([for k, v in var.distributions : length(v.aliases) == 0 || v.acm_certificate_arn != null])
    error_message = "An acm_certificate_arn is required when aliases are specified."
  }

  validation {
    condition     = alltrue([for k, v in var.distributions : v.acm_certificate_arn == null || can(regex("^arn:aws:acm:", v.acm_certificate_arn))])
    error_message = "The acm_certificate_arn must be a valid ACM certificate ARN."
  }

  validation {
    condition     = length(flatten([for k, v in var.distributions : v.aliases])) == length(distinct(flatten([for k, v in var.distributions : v.aliases])))
    error_message = "Aliases must be unique across all distributions."
  }
}

################################################################################
# Origins
################################################################################

variable "origins" {
  type = list(object({
    origin_id                = string
    domain_name              = string
    origin_path              = optional(string)
    origin_protocol_policy   = optional(string, "https-only")
    http_port                = optional(number, 80)
    https_port               = optional(number, 443)
    origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
    origin_keepalive_timeout = optional(number)
    origin_read_timeout      = optional(number)
    origin_access_control_id = optional(string)
    connection_attempts      = optional(number)
    connection_timeout       = optional(number)
    custom_headers = optional(list(object({
      name  = string
      value = string
    })), [])
    origin_shield = optional(object({
      enabled              = bool
      origin_shield_region = string
    }))
    s3_origin_enabled  = optional(bool, false)
    vpc_origin_enabled = optional(bool, false)
    vpc_origin_arn     = optional(string)
  }))
  description = "A list of origin configurations for the CloudFront distribution."

  validation {
    condition     = length(var.origins) > 0
    error_message = "At least one origin must be specified."
  }

  validation {
    condition     = length(var.origins) == length(distinct([for o in var.origins : o.origin_id]))
    error_message = "All origin_id values must be unique."
  }

  validation {
    condition     = alltrue([for o in var.origins : contains(["http-only", "https-only", "match-viewer"], o.origin_protocol_policy) if !o.s3_origin_enabled])
    error_message = "The origin_protocol_policy must be 'http-only', 'https-only', or 'match-viewer'."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.http_port >= 1 && o.http_port <= 65535])
    error_message = "The http_port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.https_port >= 1 && o.https_port <= 65535])
    error_message = "The https_port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.connection_attempts == null || (o.connection_attempts >= 1 && o.connection_attempts <= 3)])
    error_message = "The connection_attempts must be between 1 and 3."
  }

  validation {
    condition     = alltrue([for o in var.origins : o.connection_timeout == null || (o.connection_timeout >= 1 && o.connection_timeout <= 10)])
    error_message = "The connection_timeout must be between 1 and 10 seconds."
  }

  validation {
    condition     = alltrue([for o in var.origins : !o.vpc_origin_enabled || o.vpc_origin_arn != null])
    error_message = "A vpc_origin_arn is required when vpc_origin_enabled is true."
  }

  validation {
    condition     = alltrue([for o in var.origins : !(o.vpc_origin_enabled && o.s3_origin_enabled)])
    error_message = "An origin cannot enable both vpc_origin_enabled and s3_origin_enabled."
  }
}

################################################################################
# Edge Redirects
################################################################################

variable "redirect_rules" {
  type = list(object({
    source                    = string
    destination               = string
    preserve_query_string     = optional(bool, false)
    redirect_non_read_methods = optional(bool, false)
    status_code               = optional(number, 308)
  }))
  description = "Ordered viewer-request redirect rules using absolute HTTPS URLs or host-agnostic paths with named path parameters. The first matching rule wins."
  default     = []

  validation {
    condition     = length(var.redirect_rules) <= 50
    error_message = "No more than 50 redirect rules can be configured."
  }

  validation {
    condition = alltrue([
      for route in concat(
        [for rule in var.redirect_rules : rule.source],
        [for rule in var.redirect_rules : rule.destination],
      ) :
      startswith(route, "/") || (
        startswith(route, "https://") &&
        length(split("/", trimprefix(route, "https://"))[0]) <= 253 &&
        alltrue([
          for label in split(".", split("/", trimprefix(route, "https://"))[0]) :
          length(label) >= 1 && length(label) <= 63 &&
          can(regex("^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$", label))
        ])
      )
    ])
    error_message = "Each redirect source and destination must be a host-agnostic path or an absolute HTTPS URL with a valid hostname."
  }

  validation {
    condition = alltrue([
      for route in concat(
        [for rule in var.redirect_rules : rule.source],
        [for rule in var.redirect_rules : rule.destination],
      ) :
      length(route) <= 4096 && (
        can(regex(
          "^/(?:[A-Za-z0-9._~!$&'()+,;=@%-]+|:[A-Za-z][A-Za-z0-9_]*\\*?)(?:/(?:[A-Za-z0-9._~!$&'()+,;=@%-]+|:[A-Za-z][A-Za-z0-9_]*\\*?))*$",
          route,
          )) || route == "/" || can(regex(
          "^https://[A-Za-z0-9.-]+(?:/(?:[A-Za-z0-9._~!$&'()+,;=@%-]+|:[A-Za-z][A-Za-z0-9_]*\\*?)(?:/(?:[A-Za-z0-9._~!$&'()+,;=@%-]+|:[A-Za-z][A-Za-z0-9_]*\\*?))*)?$",
          route,
        ))
      )
    ])
    error_message = "Redirect routes must be at most 4096 characters and contain only URI-safe literal segments, :name parameters, or :name* catch-all parameters."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules :
      length(regexall("/:([A-Za-z][A-Za-z0-9_]*)(?:\\*)?", rule.source)) ==
      length(distinct([
        for parameter in regexall("/:([A-Za-z][A-Za-z0-9_]*)(?:\\*)?", rule.source) : parameter[0]
      ]))
    ])
    error_message = "Each named parameter may appear only once in a redirect source."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules : alltrue([
        for parameter in regexall("/:([A-Za-z][A-Za-z0-9_]*)(?:\\*)?", rule.source) :
        !contains(["__proto__", "prototype", "constructor"], parameter[0])
      ])
    ])
    error_message = "Redirect parameter names cannot be __proto__, prototype, or constructor."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules :
      length(regexall("/:[A-Za-z][A-Za-z0-9_]*\\*", rule.source)) <= 1 &&
      (length(regexall("/:[A-Za-z][A-Za-z0-9_]*\\*", rule.source)) == 0 || endswith(rule.source, "*"))
    ])
    error_message = "A redirect source may contain at most one catch-all parameter, and it must be the final segment."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules : alltrue([
        for parameter in regexall("/:([A-Za-z][A-Za-z0-9_]*)(?:\\*)?", rule.destination) :
        contains(
          [for source_parameter in regexall("/:([A-Za-z][A-Za-z0-9_]*)(?:\\*)?", rule.source) : source_parameter[0]],
          parameter[0],
        )
      ])
    ])
    error_message = "Every named parameter in a redirect destination must be declared by its source."
  }

  validation {
    condition = alltrue([
      for route in concat(
        [for rule in var.redirect_rules : rule.source],
        [for rule in var.redirect_rules : rule.destination],
      ) :
      length(regexall("%", route)) == length(regexall("%[0-9A-Fa-f]{2}", route))
    ])
    error_message = "Every percent sign in a redirect source or destination must begin a two-digit percent escape."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules : contains([301, 302, 307, 308], rule.status_code)
    ])
    error_message = "Each redirect status_code must be 301, 302, 307, or 308."
  }

  validation {
    condition = alltrue([
      for rule in var.redirect_rules :
      !rule.redirect_non_read_methods || contains([307, 308], rule.status_code)
    ])
    error_message = "Redirect rules that include non-read methods must use status code 307 or 308 to preserve the request method and body."
  }
}

################################################################################
# Default Cache Behavior
################################################################################

variable "default_cache_behavior" {
  type = object({
    target_origin_id           = string
    viewer_protocol_policy     = string
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compression_enabled        = optional(bool, true)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    trusted_key_groups         = optional(list(string), [])
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
    lambda_function_associations = optional(list(object({
      event_type             = string
      lambda_arn             = string
      body_inclusion_enabled = optional(bool, false)
    })), [])
    realtime_log_config_arn = optional(string)
  })
  description = "The default cache behavior configuration for the CloudFront distribution."

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.default_cache_behavior.viewer_protocol_policy)
    error_message = "The viewer_protocol_policy must be 'allow-all', 'https-only', or 'redirect-to-https'."
  }
}

variable "accept_header_cache_policy_creation_enabled" {
  type        = bool
  description = "Whether to create and use a module-managed cache policy for the default behavior that includes the Accept header in the cache key."
  default     = false

  validation {
    condition     = !var.accept_header_cache_policy_creation_enabled || var.default_cache_behavior.cache_policy_id == null
    error_message = "The accept_header_cache_policy_creation_enabled option cannot be used with an explicit default_cache_behavior.cache_policy_id."
  }
}

################################################################################
# Ordered Cache Behaviors
################################################################################

variable "ordered_cache_behaviors" {
  type = list(object({
    path_pattern               = string
    target_origin_id           = string
    viewer_protocol_policy     = string
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compression_enabled        = optional(bool, true)
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    trusted_key_groups         = optional(list(string), [])
    function_associations = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
    lambda_function_associations = optional(list(object({
      event_type             = string
      lambda_arn             = string
      body_inclusion_enabled = optional(bool, false)
    })), [])
    realtime_log_config_arn = optional(string)
  }))
  description = "An ordered list of cache behavior configurations. Each must include a path_pattern."
  default     = []

  validation {
    condition     = alltrue([for b in var.ordered_cache_behaviors : contains(["allow-all", "https-only", "redirect-to-https"], b.viewer_protocol_policy)])
    error_message = "The viewer_protocol_policy must be 'allow-all', 'https-only', or 'redirect-to-https'."
  }
}

################################################################################
# Distribution Settings
################################################################################

variable "price_class" {
  type        = string
  description = "The price class for the CloudFront distribution. Controls which edge locations are used."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "The price_class must be 'PriceClass_100', 'PriceClass_200', or 'PriceClass_All'."
  }
}

variable "http_version" {
  type        = string
  description = "The maximum HTTP version to support on the distribution."
  default     = "http2and3"

  validation {
    condition     = contains(["http1.1", "http2", "http2and3"], var.http_version)
    error_message = "The http_version must be 'http1.1', 'http2', or 'http2and3'."
  }
}

variable "ipv6_enabled" {
  type        = bool
  description = "Whether IPv6 is enabled for the distribution."
  default     = true
}

variable "default_root_object" {
  type        = string
  description = "The object that CloudFront returns when an end user requests the root URL (e.g., index.html)."
  default     = null
}

variable "retain_on_delete_enabled" {
  type        = bool
  description = "Whether to retain the distribution when the resource is deleted (disables instead of deleting)."
  default     = false
}

variable "deployment_wait_enabled" {
  type        = bool
  description = "Whether to wait for the distribution to be deployed before completing."
  default     = true
}

variable "additional_metrics_enabled" {
  type        = bool
  description = "Whether to enable CloudFront additional metrics in CloudWatch. This enables all 8 additional metrics for each distribution and incurs a fixed per-metric CloudWatch charge."
  default     = false
}

################################################################################
# SSL/TLS (Viewer Certificate)
################################################################################

variable "minimum_protocol_version" {
  type        = string
  description = "The minimum SSL/TLS protocol version for HTTPS viewer connections."
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "SSLv3",
      "TLSv1",
      "TLSv1_2016",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021",
    ], var.minimum_protocol_version)
    error_message = "The minimum_protocol_version must be a valid CloudFront SSL/TLS protocol version."
  }
}

variable "ssl_support_method" {
  type        = string
  description = "How CloudFront serves HTTPS requests. Only applies when acm_certificate_arn is set."
  default     = "sni-only"

  validation {
    condition     = contains(["sni-only", "vip", "static-ip"], var.ssl_support_method)
    error_message = "The ssl_support_method must be 'sni-only', 'vip', or 'static-ip'."
  }
}

################################################################################
# Restrictions
################################################################################

variable "geo_restriction_type" {
  type        = string
  description = "The type of geo restriction: none, whitelist, or blacklist."
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "The geo_restriction_type must be 'none', 'whitelist', or 'blacklist'."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "A list of ISO 3166-1-alpha-2 country codes for geo restriction."
  default     = []
}

################################################################################
# Custom Error Responses
################################################################################

variable "custom_error_responses" {
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  description = "A list of custom error response configurations."
  default     = []

  validation {
    condition     = alltrue([for r in var.custom_error_responses : contains([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], r.error_code)])
    error_message = "The error_code must be a valid HTTP error code supported by CloudFront (400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504)."
  }
}

################################################################################
# WAF
################################################################################

variable "web_acl_id" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the distribution. Must be a global (CloudFront) WAF."
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws:wafv2:", var.web_acl_id))
    error_message = "The web_acl_id must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Logging
################################################################################

variable "logging_enabled" {
  type        = bool
  description = "Enable CloudFront access logging. Defaults to true with CloudWatch Logs delivery; see logging_destination."
  default     = true
}

variable "logging_destination" {
  type        = string
  description = "Where CloudFront delivers access logs when logging_enabled is true. 'cloudwatch' uses CloudFront standard logging v2 into a module-managed CloudWatch Logs group (viewable in the Ravion UI; ingestion costs more at very high traffic). 's3' uses legacy standard logging into an S3 bucket (cheapest for high traffic)."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "s3"], var.logging_destination)
    error_message = "The logging_destination must be 'cloudwatch' or 's3'."
  }
}

variable "logging_bucket_domain_name" {
  type        = string
  description = "The domain name of an existing S3 bucket for access logs (e.g., mybucket.s3.amazonaws.com). Only applies when logging_destination is 's3'."
  default     = null
}

variable "logging_prefix" {
  type        = string
  description = "The S3 key prefix for access log files. Only applies when logging_destination is 's3'."
  default     = ""
}

variable "logging_cookies_enabled" {
  type        = bool
  description = "Whether to include cookies in access logs. Only applies when logging_destination is 's3'."
  default     = false
}

variable "logging_bucket_creation_enabled" {
  type        = bool
  description = "Whether to create a new S3 bucket for access logging. Only applies when logging_enabled is true and logging_destination is 's3'."
  default     = false
}

variable "logging_bucket_retention_days" {
  type        = number
  description = "Days to retain CloudFront access logs — the CloudWatch log group retention or the S3 lifecycle expiry on the module-created bucket, depending on logging_destination."
  default     = 90

  validation {
    condition     = var.logging_bucket_retention_days >= 1
    error_message = "The logging_bucket_retention_days must be at least 1."
  }

  validation {
    condition     = var.logging_destination != "cloudwatch" || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.logging_bucket_retention_days)
    error_message = "When logging_destination is 'cloudwatch', logging_bucket_retention_days must be a valid CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653)."
  }
}

################################################################################
# Origin Access Control
################################################################################

variable "origin_access_control_creation_enabled" {
  type        = bool
  description = "Whether to create Origin Access Control resources for S3 origins."
  default     = true
}

variable "origin_access_control_origin_type" {
  type        = string
  description = "The type of origin for the Origin Access Control."
  default     = "s3"

  validation {
    condition     = contains(["s3", "mediastore", "mediapackagev2", "lambda"], var.origin_access_control_origin_type)
    error_message = "The origin_access_control_origin_type must be 's3', 'mediastore', 'mediapackagev2', or 'lambda'."
  }
}

variable "origin_access_control_signing_behavior" {
  type        = string
  description = "The signing behavior for the Origin Access Control."
  default     = "always"

  validation {
    condition     = contains(["always", "never", "no-override"], var.origin_access_control_signing_behavior)
    error_message = "The origin_access_control_signing_behavior must be 'always', 'never', or 'no-override'."
  }
}

variable "origin_access_control_signing_protocol" {
  type        = string
  description = "The signing protocol for the Origin Access Control."
  default     = "sigv4"

  validation {
    condition     = var.origin_access_control_signing_protocol == "sigv4"
    error_message = "The origin_access_control_signing_protocol must be 'sigv4'."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
