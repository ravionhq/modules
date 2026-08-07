################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0
    error_message = "The name must not be empty."
  }

}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "load_balancer_deletion_protection_enabled" {
  type        = bool
  description = "If true, the resource cannot be deleted via the AWS API until this is set to false. Applied to all load balancers (public/private ALB and NLB) created by this module. Safe-by-default."
  default     = true
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where ECS resources will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "A list of private subnet IDs for ECS tasks and internal ALB."

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least 1 private subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.private_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All private_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = length(var.private_albs) == 0 || length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private_subnet_ids are required when private_albs is non-empty. ALBs require subnets in at least 2 availability zones for high availability."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "A list of public subnet IDs for the public ALBs/NLBs. Required if public_albs or public_nlbs is non-empty."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = length(var.public_albs) == 0 || length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public_subnet_ids are required when public_albs is non-empty. ALBs require subnets in at least 2 availability zones for high availability."
  }

  validation {
    condition     = length(var.public_nlbs) == 0 || length(var.public_subnet_ids) >= 1
    error_message = "At least 1 public_subnet_id is required when public_nlbs is non-empty."
  }
}

################################################################################
# ECS Cluster
################################################################################

variable "container_insights" {
  type        = string
  description = "CloudWatch Container Insights setting for the ECS cluster. Valid values are 'enhanced', 'enabled', and 'disabled'."
  default     = "enhanced"

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "The container_insights value must be 'enhanced', 'enabled', or 'disabled'."
  }
}

################################################################################
# Default Capacity Provider Strategy
################################################################################

variable "capacity_provider_default" {
  type        = string
  description = "Capacity provider family used for the cluster's default strategy. AWS rejects default strategies that mix Fargate and EC2 (Auto Scaling group) capacity providers, so the default strategy must commit to a single family; services can still target any attached capacity provider via their own strategy. Valid values: 'ec2', 'fargate' (also includes Fargate Spot when enabled), 'fargate_spot'. When null, defaults to 'ec2' if the EC2 capacity provider is enabled, then 'fargate' if enabled, and finally 'fargate_spot'."
  default     = null

  validation {
    condition     = var.capacity_provider_default == null || contains(["ec2", "fargate", "fargate_spot"], coalesce(var.capacity_provider_default, "null"))
    error_message = "The capacity_provider_default must be 'ec2', 'fargate', or 'fargate_spot'."
  }

  validation {
    condition     = var.capacity_provider_default != "ec2" || var.ec2_instance_type != null
    error_message = "The capacity_provider_default 'ec2' requires ec2_instance_type to be set."
  }

  validation {
    condition     = var.capacity_provider_default != "fargate" || var.fargate_enabled
    error_message = "The capacity_provider_default 'fargate' requires fargate_enabled to be true."
  }

  validation {
    condition     = var.capacity_provider_default != "fargate_spot" || var.fargate_spot_enabled
    error_message = "The capacity_provider_default 'fargate_spot' requires fargate_spot_enabled to be true."
  }
}

################################################################################
# Fargate Capacity Provider
################################################################################

variable "fargate_enabled" {
  type        = bool
  description = "Enable the Fargate capacity provider."
  default     = true
}

variable "fargate_weight" {
  type        = number
  description = "The relative weight of the Fargate capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.fargate_weight >= 0 && var.fargate_weight <= 1000
    error_message = "The fargate_weight must be between 0 and 1000."
  }
}

variable "fargate_base" {
  type        = number
  description = "The base number of tasks to run on Fargate before considering weights."
  default     = 0

  validation {
    condition     = var.fargate_base >= 0 && var.fargate_base <= 100000
    error_message = "The fargate_base must be between 0 and 100000."
  }
}

################################################################################
# Fargate Spot Capacity Provider
################################################################################

variable "fargate_spot_enabled" {
  type        = bool
  description = "Enable the Fargate Spot capacity provider."
  default     = false
}

variable "fargate_spot_weight" {
  type        = number
  description = "The relative weight of the Fargate Spot capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 1000
    error_message = "The fargate_spot_weight must be between 0 and 1000."
  }
}

variable "fargate_spot_base" {
  type        = number
  description = "The base number of tasks to run on Fargate Spot before considering weights."
  default     = 0

  validation {
    condition     = var.fargate_spot_base >= 0 && var.fargate_spot_base <= 100000
    error_message = "The fargate_spot_base must be between 0 and 100000."
  }
}

################################################################################
# EC2 Capacity Provider
################################################################################

variable "ec2_instance_type" {
  type        = string
  description = "The EC2 instance type for the ECS cluster. Set to null to disable EC2 capacity provider."
  default     = null
}

variable "ec2_ami_id" {
  type        = string
  description = "The AMI ID for EC2 instances. If null, the latest ECS-optimized AMI will be used."
  default     = null

  validation {
    condition     = var.ec2_ami_id == null || can(regex("^ami-", var.ec2_ami_id))
    error_message = "The ec2_ami_id must be a valid AMI ID starting with 'ami-'."
  }
}

variable "ec2_key_name" {
  type        = string
  description = "The name of the EC2 key pair for SSH access to instances."
  default     = null
}

variable "ec2_min_size" {
  type        = number
  description = "The minimum number of EC2 instances in the Auto Scaling Group."
  default     = 0

  validation {
    condition     = var.ec2_min_size >= 0
    error_message = "The ec2_min_size must be 0 or greater."
  }
}

variable "ec2_max_size" {
  type        = number
  description = "The maximum number of EC2 instances in the Auto Scaling Group."
  default     = 10

  validation {
    condition     = var.ec2_max_size >= 1
    error_message = "The ec2_max_size must be at least 1."
  }
}

variable "ec2_desired_capacity" {
  type        = number
  description = "The desired number of EC2 instances in the Auto Scaling Group."
  default     = 1

  validation {
    condition     = var.ec2_desired_capacity >= 0
    error_message = "The ec2_desired_capacity must be 0 or greater."
  }
}

variable "ec2_spot_enabled" {
  type        = bool
  description = "Enable Spot instances in the EC2 Auto Scaling Group using mixed instances policy."
  default     = false
}

variable "ec2_spot_instance_types" {
  type        = list(string)
  description = "Additional instance types for Spot instances. Used when ec2_spot_enabled is true."
  default     = []
}

variable "ec2_on_demand_base_capacity" {
  type        = number
  description = "The minimum number of On-Demand instances in the ASG. Used when ec2_spot_enabled is true."
  default     = 0

  validation {
    condition     = var.ec2_on_demand_base_capacity >= 0
    error_message = "The ec2_on_demand_base_capacity must be 0 or greater."
  }
}

variable "ec2_on_demand_percentage_above_base" {
  type        = number
  description = "Percentage of On-Demand instances above base capacity. Used when ec2_spot_enabled is true."
  default     = 0

  validation {
    condition     = var.ec2_on_demand_percentage_above_base >= 0 && var.ec2_on_demand_percentage_above_base <= 100
    error_message = "The ec2_on_demand_percentage_above_base must be between 0 and 100."
  }
}

variable "ec2_root_volume_size" {
  type        = number
  description = "The size of the root EBS volume in GB for EC2 instances."
  default     = 30

  validation {
    condition     = var.ec2_root_volume_size >= 8 && var.ec2_root_volume_size <= 16384
    error_message = "The ec2_root_volume_size must be between 8 and 16384 GB."
  }
}

variable "ec2_root_volume_type" {
  type        = string
  description = "The type of the root EBS volume for EC2 instances."
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.ec2_root_volume_type)
    error_message = "The ec2_root_volume_type must be 'gp2', 'gp3', 'io1', or 'io2'."
  }
}

variable "ec2_user_data" {
  type        = string
  description = "Additional user data script to run on EC2 instances (appended after ECS config)."
  default     = ""
}

variable "ec2_imdsv2_enabled" {
  type        = bool
  description = "Require IMDSv2 for EC2 instance metadata. Recommended for security."
  default     = true
}

variable "ec2_weight" {
  type        = number
  description = "The relative weight of the EC2 capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.ec2_weight >= 0 && var.ec2_weight <= 1000
    error_message = "The ec2_weight must be between 0 and 1000."
  }
}

variable "ec2_base" {
  type        = number
  description = "The base number of tasks to run on EC2 before considering weights."
  default     = 0

  validation {
    condition     = var.ec2_base >= 0 && var.ec2_base <= 100000
    error_message = "The ec2_base must be between 0 and 100000."
  }
}

variable "ec2_managed_termination_protection_enabled" {
  type        = bool
  description = "Whether managed termination protection is enabled for the EC2 capacity provider."
  default     = true
}

variable "ec2_managed_scaling_enabled" {
  type        = bool
  description = "Whether managed scaling is enabled for the EC2 capacity provider."
  default     = true
}

variable "ec2_managed_scaling_target_capacity" {
  type        = number
  description = "Target capacity percentage for managed scaling (1-100)."
  default     = 100

  validation {
    condition     = var.ec2_managed_scaling_target_capacity >= 1 && var.ec2_managed_scaling_target_capacity <= 100
    error_message = "The ec2_managed_scaling_target_capacity must be between 1 and 100."
  }
}

variable "ec2_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs to attach to EC2 instances."
  default     = []

  validation {
    condition     = alltrue([for sg in var.ec2_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All ec2_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

################################################################################
# Load Balancers
################################################################################

variable "public_albs" {
  type = list(object({
    name                       = optional(string)
    https_enabled              = optional(bool, false)
    certificate_arns           = optional(list(string), [])
    ssl_policy                 = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    idle_timeout               = optional(number, 60)
    ingress_cidr_blocks        = optional(list(string), ["0.0.0.0/0"])
    ingress_ipv6_cidr_blocks   = optional(list(string), ["::/0"])
    ingress_security_group_ids = optional(list(string), [])
    access_logs_enabled        = optional(bool, false)
    access_logs_bucket_arn     = optional(string)
    web_acl_arn                = optional(string)
  }))
  description = "Public (internet-facing) Application Load Balancers. Each entry creates one ALB with its own configuration. When name is null, the first entry is named '<name>-pub' and later entries '<name>-pub-<index+1>'."
  default     = []

  validation {
    condition     = alltrue([for lb in var.public_albs : alltrue([for arn in lb.certificate_arns : can(regex("^arn:aws:acm:", arn))])])
    error_message = "All public_albs certificate_arns must be valid ACM certificate ARNs."
  }

  validation {
    condition     = alltrue([for lb in var.public_albs : lb.idle_timeout >= 1 && lb.idle_timeout <= 4000])
    error_message = "Each public_albs idle_timeout must be between 1 and 4000 seconds."
  }

  validation {
    condition     = alltrue([for lb in var.public_albs : alltrue([for cidr in lb.ingress_cidr_blocks : can(cidrhost(cidr, 0))])])
    error_message = "All public_albs ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = alltrue([for lb in var.public_albs : alltrue([for sg in lb.ingress_security_group_ids : can(regex("^sg-", sg))])])
    error_message = "All public_albs ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition     = alltrue([for lb in var.public_albs : lb.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", coalesce(lb.access_logs_bucket_arn, "invalid")))])
    error_message = "Each public_albs access_logs_bucket_arn must be a valid S3 bucket ARN."
  }

  validation {
    condition     = alltrue([for lb in var.public_albs : lb.web_acl_arn == null || can(regex("^arn:aws:wafv2:", coalesce(lb.web_acl_arn, "invalid")))])
    error_message = "Each public_albs web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }

  validation {
    condition = alltrue([
      for idx, lb in var.public_albs :
      length(coalesce(lb.name, idx == 0 ? "${var.name}-pub" : "${var.name}-pub-${idx + 1}")) <= 32
    ])
    error_message = "Each public ALB name (explicit or derived from the module name) must be 32 characters or less."
  }

  validation {
    condition = length(distinct([
      for idx, lb in var.public_albs :
      coalesce(lb.name, idx == 0 ? "${var.name}-pub" : "${var.name}-pub-${idx + 1}")
    ])) == length(var.public_albs)
    error_message = "Each public ALB must have a unique name."
  }
}

variable "private_albs" {
  type = list(object({
    name                       = optional(string)
    https_enabled              = optional(bool, false)
    certificate_arns           = optional(list(string), [])
    ssl_policy                 = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    idle_timeout               = optional(number, 60)
    ingress_cidr_blocks        = optional(list(string), ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
    ingress_ipv6_cidr_blocks   = optional(list(string), [])
    ingress_security_group_ids = optional(list(string), [])
    access_logs_enabled        = optional(bool, false)
    access_logs_bucket_arn     = optional(string)
  }))
  description = "Private (internal) Application Load Balancers. Each entry creates one ALB with its own configuration. When name is null, the first entry is named '<name>-priv' and later entries '<name>-priv-<index+1>'."
  default     = []

  validation {
    condition     = alltrue([for lb in var.private_albs : alltrue([for arn in lb.certificate_arns : can(regex("^arn:aws:acm:", arn))])])
    error_message = "All private_albs certificate_arns must be valid ACM certificate ARNs."
  }

  validation {
    condition     = alltrue([for lb in var.private_albs : lb.idle_timeout >= 1 && lb.idle_timeout <= 4000])
    error_message = "Each private_albs idle_timeout must be between 1 and 4000 seconds."
  }

  validation {
    condition     = alltrue([for lb in var.private_albs : alltrue([for cidr in lb.ingress_cidr_blocks : can(cidrhost(cidr, 0))])])
    error_message = "All private_albs ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = alltrue([for lb in var.private_albs : alltrue([for sg in lb.ingress_security_group_ids : can(regex("^sg-", sg))])])
    error_message = "All private_albs ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition     = alltrue([for lb in var.private_albs : lb.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", coalesce(lb.access_logs_bucket_arn, "invalid")))])
    error_message = "Each private_albs access_logs_bucket_arn must be a valid S3 bucket ARN."
  }

  validation {
    condition = alltrue([
      for idx, lb in var.private_albs :
      length(coalesce(lb.name, idx == 0 ? "${var.name}-priv" : "${var.name}-priv-${idx + 1}")) <= 32
    ])
    error_message = "Each private ALB name (explicit or derived from the module name) must be 32 characters or less."
  }

  validation {
    condition = length(distinct([
      for idx, lb in var.private_albs :
      coalesce(lb.name, idx == 0 ? "${var.name}-priv" : "${var.name}-priv-${idx + 1}")
    ])) == length(var.private_albs)
    error_message = "Each private ALB must have a unique name."
  }
}

variable "public_nlbs" {
  type = list(object({
    name                              = optional(string)
    cross_zone_load_balancing_enabled = optional(bool, false)
    security_group_ids                = optional(list(string), [])
    access_logs_enabled               = optional(bool, false)
    access_logs_bucket_arn            = optional(string)
    elastic_ips_enabled               = optional(bool, false)
    elastic_ip_allocation_ids         = optional(list(string), [])
  }))
  description = "Public (internet-facing) Network Load Balancers. Each entry creates one NLB with its own configuration. When name is null, the first entry is named '<name>-pub-nlb' and later entries '<name>-pub-nlb-<index+1>'."
  default     = []

  validation {
    condition     = alltrue([for lb in var.public_nlbs : alltrue([for sg in lb.security_group_ids : can(regex("^sg-", sg))])])
    error_message = "All public_nlbs security_group_ids must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition     = alltrue([for lb in var.public_nlbs : lb.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", coalesce(lb.access_logs_bucket_arn, "invalid")))])
    error_message = "Each public_nlbs access_logs_bucket_arn must be a valid S3 bucket ARN."
  }

  validation {
    condition     = alltrue([for lb in var.public_nlbs : alltrue([for eip in lb.elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])])
    error_message = "All public_nlbs elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }

  validation {
    condition = alltrue([
      for idx, lb in var.public_nlbs :
      length(coalesce(lb.name, idx == 0 ? "${var.name}-pub-nlb" : "${var.name}-pub-nlb-${idx + 1}")) <= 32
    ])
    error_message = "Each public NLB name (explicit or derived from the module name) must be 32 characters or less."
  }

  validation {
    condition = length(distinct([
      for idx, lb in var.public_nlbs :
      coalesce(lb.name, idx == 0 ? "${var.name}-pub-nlb" : "${var.name}-pub-nlb-${idx + 1}")
    ])) == length(var.public_nlbs)
    error_message = "Each public NLB must have a unique name."
  }
}

variable "private_nlbs" {
  type = list(object({
    name                              = optional(string)
    cross_zone_load_balancing_enabled = optional(bool, false)
    security_group_ids                = optional(list(string), [])
    access_logs_enabled               = optional(bool, false)
    access_logs_bucket_arn            = optional(string)
    elastic_ips_enabled               = optional(bool, false)
    elastic_ip_allocation_ids         = optional(list(string), [])
  }))
  description = "Private (internal) Network Load Balancers. Each entry creates one NLB with its own configuration. When name is null, the first entry is named '<name>-priv-nlb' and later entries '<name>-priv-nlb-<index+1>'."
  default     = []

  validation {
    condition     = alltrue([for lb in var.private_nlbs : alltrue([for sg in lb.security_group_ids : can(regex("^sg-", sg))])])
    error_message = "All private_nlbs security_group_ids must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition     = alltrue([for lb in var.private_nlbs : lb.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", coalesce(lb.access_logs_bucket_arn, "invalid")))])
    error_message = "Each private_nlbs access_logs_bucket_arn must be a valid S3 bucket ARN."
  }

  validation {
    condition     = alltrue([for lb in var.private_nlbs : alltrue([for eip in lb.elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])])
    error_message = "All private_nlbs elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }

  validation {
    condition = alltrue([
      for idx, lb in var.private_nlbs :
      length(coalesce(lb.name, idx == 0 ? "${var.name}-priv-nlb" : "${var.name}-priv-nlb-${idx + 1}")) <= 32
    ])
    error_message = "Each private NLB name (explicit or derived from the module name) must be 32 characters or less."
  }

  validation {
    condition = length(distinct([
      for idx, lb in var.private_nlbs :
      coalesce(lb.name, idx == 0 ? "${var.name}-priv-nlb" : "${var.name}-priv-nlb-${idx + 1}")
    ])) == length(var.private_nlbs)
    error_message = "Each private NLB must have a unique name."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
