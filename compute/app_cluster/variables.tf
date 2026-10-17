################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the load balancer and the prefix of every other resource."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-32 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Ravion
################################################################################

variable "module_instance_id" {
  type        = string
  description = "The Ravion module instance id (minst_*) of this App Cluster. The wildcard certificate and custom domains are allocated to it. Injected by the runner as TF_VAR_module_instance_id inside a stack run; set it explicitly for external runs."

  validation {
    condition     = can(regex("^minst_[0-9A-Za-z]+$", var.module_instance_id))
    error_message = "The module_instance_id must be a Ravion module instance id: minst_ followed by letters and numbers."
  }
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion AWS account record id the certificates are issued in. When null, it is detected from the AWS credentials of the run."
  default     = null
}

variable "ravion_api_url" {
  type        = string
  description = "Origin of the Ravion API the router connects to. A port other than 443 is added to the router's outbound rules. Injected by the runner as TF_VAR_ravion_api_url inside a stack run. When null, the router may reach port 443 only."
  default     = null

  validation {
    condition     = var.ravion_api_url == null || can(regex("^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$", var.ravion_api_url))
    error_message = "The ravion_api_url must be an HTTPS origin with no path or trailing slash, such as https://api.ravion.com."
  }
}

################################################################################
# Domain
################################################################################

variable "ravion_domain_name" {
  type        = string
  description = "Free-form name leaf for the wildcard domain apps are served under (becomes *.<name>.<ravion-apex>). Defaults to the module instance given id."
  default     = null

  validation {
    condition     = var.ravion_domain_name == null || var.ravion_domain_name == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.ravion_domain_name))
    error_message = "The ravion_domain_name must be one DNS label: 1-63 lowercase letters, numbers, and hyphens, starting and ending with a letter or number."
  }
}

variable "module_instance_given_id" {
  type        = string
  description = "The module instance's user-facing given id (injected by the runner as TF_VAR_module_instance_given_id). Used as the default leaf for the Ravion wildcard domain."
  default     = null
}

variable "domains" {
  type        = list(string)
  description = "Custom wildcard domains attached to the load balancer beside the Ravion wildcard domain. Each entry is *.<domain> in a DNS zone you control, and every app is also served one label below it. Ravion issues one certificate for all entries and attaches it to the TLS listener; add the DNS records it provides at your DNS provider."
  default     = []

  validation {
    condition = alltrue([
      for domain in var.domains :
      can(regex("^\\*\\.([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", lower(trimsuffix(trimspace(domain), "."))))
      if trimsuffix(trimspace(domain), ".") != ""
    ])
    error_message = "Each entry of domains must be a wildcard domain: *. followed by a domain name of two or more labels, such as *.apps.example.com."
  }

  validation {
    condition     = length(var.domains) <= 10
    error_message = "The domains list holds at most 10 entries: they share one certificate."
  }

  # The longest app hostname below a custom domain, <app>-<port name>.<domain>,
  # adds 62 characters to it, and a domain name holds at most 253.
  validation {
    condition = alltrue([
      for domain in var.domains :
      length(trimprefix(lower(trimsuffix(trimspace(domain), ".")), "*.")) <= 191
    ])
    error_message = "Each entry of domains must be at most 191 characters long without its *., so that every app hostname below it is a valid domain name."
  }
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The VPC the load balancer and the router run in. The router reaches the app port range, 20000-20999, in every IPv4 range of the VPC, where the execution environment's sandbox hosts run."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the internet-facing load balancer."

  validation {
    condition     = length(var.public_subnet_ids) >= 1 && alltrue([for subnet in var.public_subnet_ids : can(regex("^subnet-", subnet))])
    error_message = "The public_subnet_ids must hold at least one subnet ID starting with 'subnet-'."
  }
}

variable "router_subnet_ids" {
  type        = list(string)
  description = "Subnets Ravion may launch the router instance in. Use private subnets with a NAT gateway: the router needs outbound HTTPS. Each must be in an Availability Zone that one of public_subnet_ids covers, because the load balancer reaches targets only in its own zones."

  validation {
    condition     = length(var.router_subnet_ids) >= 1 && alltrue([for subnet in var.router_subnet_ids : can(regex("^subnet-", subnet))])
    error_message = "The router_subnet_ids must hold at least one subnet ID starting with 'subnet-'."
  }
}

variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach the load balancer on ports 443 and 80. An empty list allows none."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "ssl_policy" {
  type        = string
  description = "Security policy of the TLS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-", var.ssl_policy))
    error_message = "The ssl_policy must be an Elastic Load Balancing security policy name starting with 'ELBSecurityPolicy-'."
  }
}

################################################################################
# Router
################################################################################

variable "ssm_enabled" {
  type        = bool
  description = "Add AWS Systems Manager Session Manager access to the router's IAM role, for operator shell access. When false the role holds only the permission to publish the router's metrics."
  default     = true
}
