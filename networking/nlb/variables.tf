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
  description = "The ID of the VPC where the NLB will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the NLB. Use public subnets for internet-facing NLBs."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "A list of additional security group IDs to attach to the NLB alongside the managed security group."
  default     = []

  validation {
    condition     = alltrue([for sg in var.additional_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All additional_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

################################################################################
# Security Group
################################################################################

variable "listener_ports" {
  type = list(object({
    port     = number
    protocol = string
  }))
  description = <<-EOF
    A list of listener port/protocol pairs to allow in the NLB security group.
    Each entry opens an ingress rule for the specified port and protocol.
    Protocol should be "tcp", "udp", or "tls" (TLS is treated as TCP at the security group level).
  EOF
  default     = []

  validation {
    condition     = alltrue([for lp in var.listener_ports : lp.port >= 1 && lp.port <= 65535])
    error_message = "All listener ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for lp in var.listener_ports : contains(["tcp", "udp", "tls", "tcp_udp"], lower(lp.protocol))])
    error_message = "All listener protocols must be one of: tcp, udp, tls, tcp_udp."
  }
}

variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "A list of IPv4 CIDR blocks allowed to access the NLB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "A list of IPv6 CIDR blocks allowed to access the NLB. Defaults to all IPv6 sources for internet-facing load balancers and no IPv6 ingress for internal load balancers."
  default     = null
}

################################################################################
# NLB Settings
################################################################################

variable "internal_load_balancer_enabled" {
  type        = bool
  description = "If true, the NLB will be internal (not internet-facing)."
  default     = false
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "If true, the resource cannot be deleted via the AWS API until this is set to false. Safe-by-default."
  default     = true
}

variable "cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing. Distributes traffic evenly across all targets in all enabled Availability Zones."
  default     = false
}

variable "dns_record_client_routing_policy" {
  type        = string
  description = "How traffic is distributed among NLB AZs. Use 'any_availability_zone' to route to any healthy AZ, or 'availability_zone_affinity' to prefer the client's AZ."
  default     = null

  validation {
    condition     = var.dns_record_client_routing_policy == null || contains(["any_availability_zone", "availability_zone_affinity", "partial_availability_zone_affinity"], var.dns_record_client_routing_policy)
    error_message = "The dns_record_client_routing_policy must be 'any_availability_zone', 'availability_zone_affinity', or 'partial_availability_zone_affinity'."
  }
}

variable "enforce_security_group_inbound_rules_on_private_link_traffic" {
  type        = string
  description = "Whether inbound security group rules are enforced for traffic from PrivateLink."
  default     = null

  validation {
    condition     = var.enforce_security_group_inbound_rules_on_private_link_traffic == null || contains(["on", "off"], var.enforce_security_group_inbound_rules_on_private_link_traffic)
    error_message = "The enforce_security_group_inbound_rules_on_private_link_traffic must be 'on' or 'off'."
  }
}

################################################################################
# Elastic IPs (Static IPs)
################################################################################

variable "elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the NLB using Elastic IPs. When enabled, elastic_ip_allocation_ids must be provided."
  default     = false
}

variable "elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the NLB, one per subnet. Required if elastic_ips_enabled is true."
  default     = []

  validation {
    condition     = alltrue([for eip in var.elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Access Logs
################################################################################

variable "access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the NLB."
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

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
