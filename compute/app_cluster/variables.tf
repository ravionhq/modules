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
  description = "The Ravion module instance id (minst_*) of this App Cluster. The wildcard certificate and custom domains are allocated to it, and it owns the sandbox pool. Injected by the runner as TF_VAR_module_instance_id inside a stack run; set it explicitly for external runs."

  validation {
    condition     = can(regex("^minst_[0-9A-Za-z]+$", var.module_instance_id))
    error_message = "The module_instance_id must be a Ravion module instance id: minst_ followed by letters and numbers."
  }
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion AWS account record id the wildcard certificate is issued in and the sandbox pool runs in. When null, it is detected from the AWS credentials of the run."
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
  description = "Custom wildcard domains attached to the load balancer beside the Ravion wildcard domain. Each entry is *.<domain> in a DNS zone you control. Ravion issues one certificate for all entries and attaches it to the TLS listener; add the DNS records it provides at your DNS provider."
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
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The VPC the load balancer, the router and the sandbox hosts run in."

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

variable "host_subnet_id" {
  type        = string
  description = "Subnet Ravion launches the sandbox hosts in. Use a private subnet with a NAT gateway: hosts need outbound internet access."

  validation {
    condition     = can(regex("^subnet-", var.host_subnet_id))
    error_message = "The host_subnet_id must be a subnet ID starting with 'subnet-'."
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

################################################################################
# Sandbox hosts
################################################################################

variable "host_instance_types" {
  type = list(object({
    type                 = string
    disk_gib             = optional(number, 130)
    disk_iops            = optional(number, 3000)
    disk_throughput_mbps = optional(number, 125)
  }))
  description = "EC2 instance types the sandbox pool may launch, each with its root volume's size in GiB, provisioned IOPS and throughput in MB/s. Each type must support nested virtualization. Empty lets Ravion choose from the region's c8id, m8id, r8id, i7i and i7ie types."
  default     = []

  validation {
    condition     = alltrue([for instance_type in var.host_instance_types : can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", instance_type.type))])
    error_message = "Every type in host_instance_types must be an EC2 instance type such as c8id.4xlarge."
  }

  validation {
    condition     = length(distinct([for instance_type in var.host_instance_types : instance_type.type])) == length(var.host_instance_types)
    error_message = "Each type in host_instance_types must be listed once."
  }

  validation {
    condition     = alltrue([for instance_type in var.host_instance_types : instance_type.disk_gib >= 30 && instance_type.disk_gib <= 16384 && floor(instance_type.disk_gib) == instance_type.disk_gib])
    error_message = "Every disk_gib in host_instance_types must be a whole number from 30 to 16384."
  }

  validation {
    condition     = alltrue([for instance_type in var.host_instance_types : instance_type.disk_iops >= 3000 && instance_type.disk_iops <= 16000 && floor(instance_type.disk_iops) == instance_type.disk_iops])
    error_message = "Every disk_iops in host_instance_types must be a whole number from 3000 to 16000."
  }

  validation {
    condition     = alltrue([for instance_type in var.host_instance_types : instance_type.disk_throughput_mbps >= 125 && instance_type.disk_throughput_mbps <= 1000 && floor(instance_type.disk_throughput_mbps) == instance_type.disk_throughput_mbps])
    error_message = "Every disk_throughput_mbps in host_instance_types must be a whole number from 125 to 1000."
  }
}

variable "host_capacity_types" {
  type        = list(string)
  description = "The markets the sandbox pool buys hosts in: ON_DEMAND, and SPOT to also place interruptible sandboxes on Spot hosts, which AWS can reclaim with two minutes' notice."
  default     = ["ON_DEMAND"]

  validation {
    condition     = contains(var.host_capacity_types, "ON_DEMAND")
    error_message = "The host_capacity_types must include ON_DEMAND."
  }

  validation {
    condition     = alltrue([for capacity_type in var.host_capacity_types : contains(["ON_DEMAND", "SPOT"], capacity_type)]) && length(distinct(var.host_capacity_types)) == length(var.host_capacity_types)
    error_message = "The host_capacity_types may hold ON_DEMAND and SPOT, each once."
  }
}

variable "host_reserve_policy" {
  type = object({
    type        = string
    window_days = optional(number, 7)
    value       = optional(number, 0)
  })
  description = "How many hosts the sandbox pool keeps parked and ready. NONE keeps none, so a deploy after a quiet period waits for a host to launch. FIXED keeps value hosts. PEAK keeps as many as the busiest minute of the last window_days used, and ROLLING_AVERAGE the mean of their daily peaks."
  default = {
    type = "NONE"
  }

  validation {
    condition     = contains(["NONE", "FIXED", "PEAK", "ROLLING_AVERAGE"], var.host_reserve_policy.type)
    error_message = "The host_reserve_policy type must be NONE, FIXED, PEAK or ROLLING_AVERAGE."
  }

  validation {
    condition     = var.host_reserve_policy.window_days >= 1 && var.host_reserve_policy.window_days <= 90 && floor(var.host_reserve_policy.window_days) == var.host_reserve_policy.window_days
    error_message = "The host_reserve_policy window_days must be a whole number from 1 to 90."
  }

  validation {
    condition     = var.host_reserve_policy.value >= 0 && floor(var.host_reserve_policy.value) == var.host_reserve_policy.value
    error_message = "The host_reserve_policy value must be a whole number of hosts, 0 or more."
  }
}

variable "max_hosts" {
  type        = number
  description = "The most sandbox hosts the pool runs at once, parked hosts included. Apps that find no room once the pool has this many wait for room on them."
  default     = 10

  validation {
    condition     = var.max_hosts >= 1 && var.max_hosts <= 100 && floor(var.max_hosts) == var.max_hosts
    error_message = "The max_hosts must be a whole number from 1 to 100."
  }
}
