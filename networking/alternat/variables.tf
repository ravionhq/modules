################################################################################
# General
################################################################################

variable "region" {
  type        = string
  description = "AWS region of the VPC."
}

variable "name" {
  type        = string
  description = "Name prefix for every resource this module creates. Must be unique per AWS account and region."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,26}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-28 characters, contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# VPC
################################################################################

variable "vpc_id" {
  type        = string
  description = "ID of the VPC whose private subnets egress through the NAT instances."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "The vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets the NAT instances run in. Each NAT instance runs in the first public subnet of its availability zone."

  validation {
    condition     = length(var.public_subnet_ids) > 0
    error_message = "At least one public subnet is required."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets whose internet egress the NAT instances take over. Their route tables are discovered, and alterNAT manages the 0.0.0.0/0 route in each."

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet is required."
  }
}

################################################################################
# NAT instances
################################################################################

variable "high_availability_enabled" {
  type        = bool
  description = "Run one NAT instance per availability zone that has its own private route table, so no traffic crosses zones. When false, one NAT instance serves every private route table."
  default     = true
}

variable "nat_instance_type" {
  type        = string
  description = "EC2 instance type for the NAT instances. The architecture of the AMI and Lambda functions follows it. Instances under 32 vCPUs get at most 5 Gbps of internet bandwidth."
  default     = "c7gn.medium"
}

variable "nat_instance_ami_id" {
  type        = string
  description = "AMI for the NAT instances. Defaults to the latest Amazon Linux 2023 minimal kernel 6.18 AMI for the instance type's architecture."
  default     = null

  validation {
    condition     = var.nat_instance_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.nat_instance_ami_id))
    error_message = "The nat_instance_ami_id must be an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "nat_instance_eip_allocation_ids" {
  type        = list(string)
  description = "Pre-allocated Elastic IP allocation IDs for the NAT instances, one per NAT instance, to keep their public IPs stable across replacements of this module. Leave empty to allocate new Elastic IPs."
  default     = []

  validation {
    condition     = alltrue([for id in var.nat_instance_eip_allocation_ids : can(regex("^eipalloc-[0-9a-f]+$", id))])
    error_message = "Each Elastic IP allocation ID must look like eipalloc-0123456789abcdef0."
  }
}

variable "max_instance_lifetime_days" {
  type        = number
  description = "Replace each NAT instance after this many days so it picks up the latest AMI. Replacement drops the instance's open connections. Set 0 to never replace."
  default     = 14

  validation {
    condition     = var.max_instance_lifetime_days == 0 || (var.max_instance_lifetime_days >= 1 && var.max_instance_lifetime_days <= 365)
    error_message = "The max_instance_lifetime_days must be 0 or between 1 and 365."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks, besides the VPC's own CIDR blocks, that may route through the NAT instances (for example peered VPCs)."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "Each allowed CIDR block must be a valid IPv4 CIDR."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups whose members may route through the NAT instances, in addition to the VPC's CIDR blocks."
  default     = []
}

variable "ssm_enabled" {
  type        = bool
  description = "Allow Systems Manager Session Manager access to the NAT instances. Required for NAT restore."
  default     = true
}

variable "cloudwatch_agent_enabled" {
  type        = bool
  description = "Run the CloudWatch agent on the NAT instances to publish per-interface network metrics. Custom metrics are billed."
  default     = false
}

variable "nat_instance_user_data_pre_install" {
  type        = string
  description = "Shell script run on NAT instance boot before alterNAT configures NAT."
  default     = ""
}

variable "nat_instance_user_data_post_install" {
  type        = string
  description = "Shell script run on NAT instance boot after alterNAT configures NAT."
  default     = ""
}

variable "nat_instance_key_name" {
  type        = string
  description = "EC2 key pair for SSH access to the NAT instances. Prefer Session Manager."
  default     = null
}

################################################################################
# Fallback NAT gateway
################################################################################

variable "fallback_nat_gateway_mode" {
  type        = string
  description = "Where failover traffic goes when a NAT instance is unhealthy. `existing` reuses NAT gateways already in the VPC; `create` creates a standby NAT gateway in each NAT instance's public subnet."
  default     = "existing"

  validation {
    condition     = contains(["existing", "create"], var.fallback_nat_gateway_mode)
    error_message = "The fallback_nat_gateway_mode must be existing or create."
  }
}

variable "fallback_nat_gateway_id" {
  type        = string
  description = "With the existing mode, the NAT gateway every NAT instance fails over to. Leave empty to use the VPC's only NAT gateway, or, when there are several, the one in each NAT instance's public subnet."
  default     = null

  validation {
    condition     = var.fallback_nat_gateway_id == null || can(regex("^nat-[0-9a-f]+$", var.fallback_nat_gateway_id))
    error_message = "The fallback_nat_gateway_id must be a NAT gateway ID such as nat-0123456789abcdef0."
  }
}

variable "fallback_nat_gateway_eip_allocation_ids" {
  type        = map(string)
  description = "With the create mode, pre-allocated Elastic IP allocation IDs for the standby NAT gateways, keyed by availability zone name."
  default     = {}
}

variable "nat_restore_enabled" {
  type        = bool
  description = "Move traffic back from the fallback NAT gateway to a NAT instance once it is healthy again, without waiting for the instance to be replaced. Requires SSM."
  default     = true
}

################################################################################
# Connectivity checks
################################################################################

variable "connectivity_check_urls" {
  type        = list(string)
  description = "URLs the connectivity tester requests every minute from each AZ. Traffic fails over only when all of them are unreachable."
  default     = ["https://www.example.com", "https://www.google.com"]

  validation {
    condition     = length(var.connectivity_check_urls) > 0 && alltrue([for url in var.connectivity_check_urls : can(regex("^https?://", url))])
    error_message = "At least one connectivity check URL is required, and each must start with http:// or https://."
  }
}

################################################################################
# VPC endpoints
################################################################################

variable "ec2_endpoint_enabled" {
  type        = bool
  description = "Create an EC2 interface endpoint so the failover Lambda can reach the EC2 API when internet egress is down. Disable only if the VPC already has one with private DNS."
  default     = true
}

variable "s3_gateway_endpoint_enabled" {
  type        = bool
  description = "Create a free S3 gateway endpoint on the managed route tables so S3 traffic bypasses the NAT. Disable if the VPC already has one."
  default     = false
}

variable "dynamodb_gateway_endpoint_enabled" {
  type        = bool
  description = "Create a free DynamoDB gateway endpoint on the managed route tables so DynamoDB traffic bypasses the NAT. Disable if the VPC already has one."
  default     = false
}
