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

  validation {
    condition     = !var.public_alb_enabled || length(var.name) <= 28
    error_message = "The name must be 28 characters or less when public_alb_enabled is true so the public ALB name does not exceed the 32 character AWS limit."
  }

  validation {
    condition     = !var.private_alb_enabled || length(var.name) <= 27
    error_message = "The name must be 27 characters or less when private_alb_enabled is true so the private ALB name does not exceed the 32 character AWS limit."
  }

  validation {
    condition     = !var.public_nlb_enabled || length(var.name) <= 24
    error_message = "The name must be 24 characters or less when public_nlb_enabled is true so the public NLB name does not exceed the 32 character AWS limit."
  }

  validation {
    condition     = !var.private_nlb_enabled || length(var.name) <= 23
    error_message = "The name must be 23 characters or less when private_nlb_enabled is true so the private NLB name does not exceed the 32 character AWS limit."
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
    condition     = !var.private_alb_enabled || length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private_subnet_ids are required when private_alb_enabled is true. ALBs require subnets in at least 2 availability zones for high availability."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "A list of public subnet IDs for the public ALB/NLB. Required if public_alb_enabled or public_nlb_enabled is true."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = !var.public_alb_enabled || length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public_subnet_ids are required when public_alb_enabled is true. ALBs require subnets in at least 2 availability zones for high availability."
  }

  validation {
    condition     = !var.public_nlb_enabled || length(var.public_subnet_ids) >= 1
    error_message = "At least 1 public_subnet_id is required when public_nlb_enabled is true."
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
# Public ALB
################################################################################

variable "public_alb_enabled" {
  type        = bool
  description = "Enable a public (internet-facing) Application Load Balancer."
  default     = false
}

variable "public_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the public ALB."
  default     = false
}

variable "public_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the public ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.public_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All public_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "public_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the public ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "public_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the public ALB in seconds."
  default     = 60

  validation {
    condition     = var.public_alb_idle_timeout >= 1 && var.public_alb_idle_timeout <= 4000
    error_message = "The public_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "public_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the public ALB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.public_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All public_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "public_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the public ALB."
  default     = ["::/0"]
}

variable "public_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the public ALB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public ALB."
  default     = false
}

variable "public_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public ALB access logs."
  default     = null

  validation {
    condition     = var.public_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_alb_access_logs_bucket_arn))
    error_message = "The public_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_alb_web_acl_arn" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the public ALB."
  default     = null

  validation {
    condition     = var.public_alb_web_acl_arn == null || can(regex("^arn:aws:wafv2:", var.public_alb_web_acl_arn))
    error_message = "The public_alb_web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Private ALB
################################################################################

variable "private_alb_enabled" {
  type        = bool
  description = "Enable a private (internal) Application Load Balancer."
  default     = false
}

variable "private_alb_https_enabled" {
  type        = bool
  description = "Enable HTTPS listener on the private ALB."
  default     = false
}

variable "private_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the private ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.private_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All private_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "private_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the private ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "private_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the private ALB in seconds."
  default     = 60

  validation {
    condition     = var.private_alb_idle_timeout >= 1 && var.private_alb_idle_timeout <= 4000
    error_message = "The private_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "private_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the private ALB."
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.private_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All private_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "private_alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to access the private ALB. Defaults to no IPv6 ingress; RFC1918 has no IPv6 equivalent."
  default     = []
}

variable "private_alb_ingress_security_group_ids" {
  type        = list(string)
  description = "Security group IDs whose members are allowed to access the private ALB. Useful for sources without static CIDRs, such as CloudFront VPC origins."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_alb_ingress_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_alb_ingress_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_alb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private ALB."
  default     = false
}

variable "private_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private ALB access logs."
  default     = null

  validation {
    condition     = var.private_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_alb_access_logs_bucket_arn))
    error_message = "The private_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

################################################################################
# Public NLB
################################################################################

variable "public_nlb_enabled" {
  type        = bool
  description = "Enable a public (internet-facing) Network Load Balancer."
  default     = false
}

variable "public_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the public NLB."
  default     = false
}

variable "public_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to attach to the public NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the public NLB."
  default     = false
}

variable "public_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public NLB access logs."
  default     = null

  validation {
    condition     = var.public_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_nlb_access_logs_bucket_arn))
    error_message = "The public_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the public NLB using Elastic IPs."
  default     = false
}

variable "public_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the public NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.public_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All public_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Private NLB
################################################################################

variable "private_nlb_enabled" {
  type        = bool
  description = "Enable a private (internal) Network Load Balancer."
  default     = false
}

variable "private_nlb_cross_zone_load_balancing_enabled" {
  type        = bool
  description = "Enable cross-zone load balancing for the private NLB."
  default     = false
}

variable "private_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to attach to the private NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_nlb_access_logs_enabled" {
  type        = bool
  description = "Enable access logging for the private NLB."
  default     = false
}

variable "private_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private NLB access logs."
  default     = null

  validation {
    condition     = var.private_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_nlb_access_logs_bucket_arn))
    error_message = "The private_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "private_nlb_elastic_ips_enabled" {
  type        = bool
  description = "Enable static IP addresses for the private NLB using Elastic IPs."
  default     = false
}

variable "private_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the private NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.private_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All private_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Compliance: log retention and load balancer alarms
################################################################################

variable "log_retention_days" {
  type        = number
  description = "Default CloudWatch Logs retention (days) that ECS services in this cluster inherit. Exposed as an output; the cluster itself creates no log groups. 0 retains logs indefinitely."
  default     = 90
  nullable    = false

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "The log_retention_days must be one of the values accepted by CloudWatch Logs (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653)."
  }
}

variable "alb_cloudwatch_alarms_creation_enabled" {
  type        = bool
  description = "Create CloudWatch alarms for 5xx responses and target response time on the public and private ALBs."
  default     = true
  nullable    = false
}

variable "alb_cloudwatch_alarm_elb_5xx_threshold" {
  type        = number
  description = "Number of load-balancer-generated 5xx responses (HTTPCode_ELB_5XX_Count, summed per period) above which the ALB alarm fires."
  default     = 10
  nullable    = false

  validation {
    condition     = var.alb_cloudwatch_alarm_elb_5xx_threshold >= 0
    error_message = "The alb_cloudwatch_alarm_elb_5xx_threshold must be at least 0."
  }
}

variable "alb_cloudwatch_alarm_target_5xx_threshold" {
  type        = number
  description = "Number of target-generated 5xx responses (HTTPCode_Target_5XX_Count, summed per period) above which the ALB alarm fires."
  default     = 10
  nullable    = false

  validation {
    condition     = var.alb_cloudwatch_alarm_target_5xx_threshold >= 0
    error_message = "The alb_cloudwatch_alarm_target_5xx_threshold must be at least 0."
  }
}

variable "alb_cloudwatch_alarm_target_response_time_threshold" {
  type        = number
  description = "Average target response time in seconds (TargetResponseTime) above which the ALB alarm fires."
  default     = 1
  nullable    = false

  validation {
    condition     = var.alb_cloudwatch_alarm_target_response_time_threshold > 0
    error_message = "The alb_cloudwatch_alarm_target_response_time_threshold must be greater than 0."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  type        = number
  description = "The number of periods over which data is compared to the threshold."
  default     = 2
  nullable    = false

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "The cloudwatch_alarm_evaluation_periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period" {
  type        = number
  description = "The period in seconds over which the statistic is applied. AWS service metrics are published at one-minute resolution, so 60 is the shortest useful period."
  default     = 300
  nullable    = false

  validation {
    condition     = contains([60, 300, 900, 3600], var.cloudwatch_alarm_period)
    error_message = "The cloudwatch_alarm_period must be one of: 60, 300, 900, or 3600 seconds. AWS service metrics are published at one-minute resolution, so shorter periods never receive datapoints."
  }
}

variable "cloudwatch_alarm_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when a CloudWatch alarm transitions to ALARM state."
  default     = []
  nullable    = false
}

variable "cloudwatch_ok_actions" {
  type        = list(string)
  description = "A list of ARNs to notify when a CloudWatch alarm transitions to OK state."
  default     = []
  nullable    = false
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}
