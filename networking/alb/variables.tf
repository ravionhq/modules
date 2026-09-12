################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 32
    error_message = "The name must be between 1 and 32 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the ALB will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the ALB. Use public subnets for internet-facing ALBs."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for high availability."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

################################################################################
# ALB Settings
################################################################################

variable "internal_load_balancer_enabled" {
  type        = bool
  description = "If true, the ALB will be internal (not internet-facing)."
  default     = false
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, the resource cannot be deleted via the AWS API until this is set to false. Safe-by-default."
  default     = true
}

variable "idle_timeout" {
  type        = number
  description = "The time in seconds that the connection is allowed to be idle."
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "The idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "http2_enabled" {
  type        = bool
  description = "Enable HTTP/2 on the ALB."
  default     = true
}

variable "invalid_header_drop_enabled" {
  type        = bool
  description = "Drop HTTP headers with invalid header fields. Recommended for security."
  default     = true
}

variable "desync_mitigation_mode" {
  type        = string
  description = "Determines how the ALB handles requests that might pose a security risk due to HTTP desync."
  default     = "defensive"

  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "The desync_mitigation_mode must be 'monitor', 'defensive', or 'strictest'."
  }
}

variable "host_header_preservation_enabled" {
  type        = bool
  description = "Preserve the Host header in the HTTP request and send it to the target without modification."
  default     = false
}

variable "xff_header_processing_mode" {
  type        = string
  description = "Determines how the ALB modifies the X-Forwarded-For header in the HTTP request."
  default     = "append"

  validation {
    condition     = contains(["append", "preserve", "remove"], var.xff_header_processing_mode)
    error_message = "The xff_header_processing_mode must be 'append', 'preserve', or 'remove'."
  }
}

variable "waf_fail_open_enabled" {
  type        = bool
  description = "Enable WAF fail open. If true, traffic is allowed when WAF is unavailable."
  default     = false
}

################################################################################
# Listeners
################################################################################

variable "http_listener_enabled" {
  type        = bool
  description = "Create an HTTP listener on port 80."
  default     = true
}

variable "https_listener_enabled" {
  type        = bool
  description = "Create an HTTPS listener on port 443. Requires certificate_arns to be provided."
  default     = false
}

variable "http_listener_port" {
  type        = number
  description = "The port for the HTTP listener."
  default     = 80

  validation {
    condition     = var.http_listener_port >= 1 && var.http_listener_port <= 65535
    error_message = "The http_listener_port must be between 1 and 65535."
  }
}

variable "https_listener_port" {
  type        = number
  description = "The port for the HTTPS listener."
  default     = 443

  validation {
    condition     = var.https_listener_port >= 1 && var.https_listener_port <= 65535
    error_message = "The https_listener_port must be between 1 and 65535."
  }
}

variable "http_to_https_redirect_enabled" {
  type        = bool
  description = "Redirect HTTP traffic to HTTPS. Only applies when both listeners are enabled."
  default     = true
}

################################################################################
# SSL/TLS
################################################################################

variable "certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI. Required if https_listener_enabled is true."
  default     = []

  validation {
    condition     = alltrue([for arn in var.certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "ssl_policy" {
  type        = string
  description = "The SSL policy for the HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

################################################################################
# Default Action (Fixed Response)
################################################################################

variable "default_action_status_code" {
  type        = number
  description = "The HTTP status code to return when no listener rule matches."
  default     = 503

  validation {
    condition     = var.default_action_status_code >= 200 && var.default_action_status_code <= 599
    error_message = "The default_action_status_code must be between 200 and 599."
  }
}

variable "default_action_content_type" {
  type        = string
  description = "The content type for the fixed response."
  default     = "text/plain"

  validation {
    condition     = contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.default_action_content_type)
    error_message = "The default_action_content_type must be a valid content type."
  }
}

variable "default_action_message" {
  type        = string
  description = "The message body for the fixed response."
  default     = "Service Unavailable"

  validation {
    condition     = length(var.default_action_message) <= 1024
    error_message = "The default_action_message must be 1024 characters or less."
  }
}

################################################################################
# Security Group
################################################################################

variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "A list of IPv4 CIDR blocks allowed to access the ALB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "A list of IPv6 CIDR blocks allowed to access the ALB. Defaults to all IPv6 sources for internet-facing load balancers and no IPv6 ingress for internal load balancers."
  default     = null
}

variable "ingress_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs whose members are allowed to access the ALB. Ingress rules are created on each enabled listener port."
  default     = []

  validation {
    condition     = length(distinct(var.ingress_security_group_ids)) == length(var.ingress_security_group_ids) && alltrue([for sg in var.ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All ingress_security_group_ids must be unique, valid security group IDs starting with 'sg-'."
  }
}

################################################################################
# Access Logs
################################################################################

variable "access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the ALB."
  default     = false
}

variable "access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for access logs. If null and access logs are enabled, a new bucket will be created."
  default     = null

  validation {
    condition     = var.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.access_logs_bucket_arn))
    error_message = "The access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "access_logs_prefix" {
  type        = string
  description = "The S3 prefix for access logs."
  default     = ""
}

variable "access_logs_retention_days" {
  type        = number
  description = "The number of days to retain access logs in S3."
  default     = 90

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "The access_logs_retention_days must be at least 1."
  }
}

variable "access_logs_kms_key_id" {
  type        = string
  description = "KMS key ID for S3 bucket encryption. If null, uses AES256 (SSE-S3)."
  default     = null

  validation {
    condition     = var.access_logs_kms_key_id == null || can(regex("^(arn:aws:kms:|alias/)", var.access_logs_kms_key_id))
    error_message = "The access_logs_kms_key_id must be a valid KMS key ARN or alias."
  }
}

variable "access_logs_versioning_enabled" {
  type        = bool
  description = "Enable versioning for the access logs S3 bucket."
  default     = false
}

################################################################################
# WAF
################################################################################

variable "waf_association_enabled" {
  type        = bool
  description = "Whether to associate a WAF Web ACL with the ALB. Set to true when providing web_acl_arn."
  default     = false
}

variable "web_acl_arn" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the ALB. Required when waf_association_enabled is true."
  default     = null

  validation {
    condition     = var.web_acl_arn == null || can(regex("^arn:aws:wafv2:", var.web_acl_arn))
    error_message = "The web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
