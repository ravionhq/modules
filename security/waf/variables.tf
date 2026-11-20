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
