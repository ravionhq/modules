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
  description = "The Ravion module instance id (minst_*) this preview ingress belongs to. It is the router's identity: the instance is tagged with it, enrolls with it, and receives the previews of this module instance's wildcard domain. Injected by the runner as TF_VAR_module_instance_id inside a stack run; set it explicitly for external runs."

  validation {
    condition     = can(regex("^minst_[0-9A-Za-z]+$", var.module_instance_id))
    error_message = "The module_instance_id must be a Ravion module instance id: minst_ followed by letters and numbers."
  }
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion AWS account record id (aws_*) the wildcard certificate is issued in. When null, it is detected from the AWS credentials of the run."
  default     = null
}

variable "ravion_api_url" {
  type        = string
  description = "Origin of the Ravion API the router connects to. Injected by the runner as TF_VAR_ravion_api_url inside a stack run; set it explicitly for external runs."

  validation {
    condition     = can(regex("^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$", var.ravion_api_url))
    error_message = "The ravion_api_url must be an HTTPS origin with no path or trailing slash, such as https://api.ravion.com."
  }
}

################################################################################
# Domain
################################################################################

variable "ravion_domain_name" {
  type        = string
  description = "Free-form name leaf for the wildcard domain previews are served under (becomes *.<name>.<ravion-apex>). Defaults to the module instance given id."
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
  description = "Custom wildcard domains previews can be served under, beside the Ravion wildcard domain. Each entry is *.<domain> in a DNS zone you control, and a preview takes one hostname below it. Ravion issues one certificate for all entries and attaches it to the TLS listener; add the DNS records it provides at your DNS provider."
  default     = []

  validation {
    condition = alltrue([
      for domain in var.domains :
      can(regex("^\\*\\.([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", lower(trimsuffix(trimspace(domain), "."))))
      if trimsuffix(trimspace(domain), ".") != ""
    ])
    error_message = "Each entry of domains must be a wildcard domain: *. followed by a domain name of two or more labels, such as *.preview.example.com."
  }

  validation {
    condition     = length(var.domains) <= 10
    error_message = "The domains list holds at most 10 entries: they share one certificate."
  }
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The VPC the load balancer and the router run in. It must be the VPC of the sandboxes whose previews the router serves."

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
  description = "Subnets the router instance launches in. Use private subnets with a NAT gateway, or public subnets together with router_public_ip_enabled: the router needs outbound HTTPS. Each must be in an Availability Zone that one of public_subnet_ids covers, because the load balancer reaches targets only in its own zones."

  validation {
    condition     = length(var.router_subnet_ids) >= 1 && alltrue([for subnet in var.router_subnet_ids : can(regex("^subnet-", subnet))])
    error_message = "The router_subnet_ids must hold at least one subnet ID starting with 'subnet-'."
  }
}

variable "router_public_ip_enabled" {
  type        = bool
  description = "Give the router instance a public IPv4 address. Needed only when router_subnet_ids are public subnets. The instance still accepts traffic from the load balancer alone."
  default     = false
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

variable "sandbox_host_security_groups" {
  type = list(object({
    name = string
    id   = string
  }))
  description = "Security groups of the sandbox hosts whose previews the router serves. Each gets one inbound rule that admits the router's security group on the preview port range, and the router one outbound rule to it. The router cannot reach a sandbox host outside these groups. `name` is a label you choose that names the group's rules, so `id` can be a group created in the same apply."
  default     = []

  validation {
    condition     = alltrue([for group in var.sandbox_host_security_groups : can(regex("^sg-[0-9a-f]+$", group.id))])
    error_message = "Every id in sandbox_host_security_groups must be a security group ID starting with 'sg-'."
  }

  validation {
    condition     = alltrue([for group in var.sandbox_host_security_groups : length(group.name) > 0])
    error_message = "Every name in sandbox_host_security_groups must be non-empty."
  }

  validation {
    condition     = length(distinct([for group in var.sandbox_host_security_groups : group.name])) == length(var.sandbox_host_security_groups)
    error_message = "Each name in sandbox_host_security_groups must be used once."
  }

  validation {
    condition     = length(distinct([for group in var.sandbox_host_security_groups : group.id])) == length(var.sandbox_host_security_groups)
    error_message = "Each security group in sandbox_host_security_groups must be listed once."
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
# Router instance
################################################################################

variable "instance_type" {
  type        = string
  description = "EC2 instance type of the router. Its architecture must match the image's."
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "The instance_type must be an EC2 instance type such as t3.micro."
  }
}

variable "image_id" {
  type        = string
  description = "AMI the router instance boots. When null, the newest image of image_owner matching image_name_pattern and the instance type's architecture is used. The image must carry systemd and the preview router at /usr/local/bin/preview-router, as the preview router images Ravion publishes do."
  default     = null

  validation {
    condition     = var.image_id == null || can(regex("^ami-[0-9a-f]+$", var.image_id))
    error_message = "The image_id must be an AMI ID starting with 'ami-'."
  }
}

variable "image_owner" {
  type        = string
  description = "AWS account that publishes the router image looked up when image_id is null: a 12-digit account ID, or the alias self, amazon or aws-marketplace. Defaults to the account Ravion publishes its images from."
  default     = "600013814144"

  validation {
    condition     = can(regex("^([0-9]{12}|self|amazon|aws-marketplace)$", var.image_owner))
    error_message = "The image_owner must be a 12-digit AWS account ID, or one of self, amazon, aws-marketplace."
  }
}

variable "image_name_pattern" {
  type        = string
  description = "AMI name pattern of the router image looked up when image_id is null. Use * as a wildcard."
  default     = "ravion-preview-router-*"

  validation {
    condition     = length(var.image_name_pattern) > 0
    error_message = "The image_name_pattern must not be empty."
  }
}

variable "router_enabled" {
  type        = bool
  description = "Run the router. When false the Auto Scaling group keeps no instance and no preview URL answers, while the load balancer, certificate and domains stay in place for when it is turned on again."
  default     = true
}

variable "ssm_enabled" {
  type        = bool
  description = "Give the router instance an IAM role that allows AWS Systems Manager Session Manager and nothing else, for operator shell access. When false the instance has no IAM role. The image must carry the SSM Agent."
  default     = true
}
