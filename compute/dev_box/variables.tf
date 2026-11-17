################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the dev box. Prefixes the instance, security group, IAM role, and schedule names."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,26}[a-z0-9])?$", var.name))
    error_message = "The name must be 1-28 lowercase letters, numbers, and hyphens, and start and end with a letter or number."
  }
}

variable "region" {
  type        = string
  description = "AWS region for the dev box. Defaults to the provider region."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Networking
################################################################################

variable "vpc_id" {
  type        = string
  description = "VPC that the dev box runs in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "The vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the dev box may run in. The instance is placed in the first one; changing it replaces the instance."

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "Provide at least one subnet ID such as subnet-0123456789abcdef0."
  }
}

variable "public_ip_assignment_enabled" {
  type        = bool
  description = "Assign a public IPv4 address. Requires a public subnet. Changing it replaces the instance."
  default     = false
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Additional security groups attached to the dev box."
  default     = []
}

variable "ssh_allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach port 22. Leave empty to keep SSH closed and connect with Session Manager."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ssh_allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "Every ssh_allowed_cidr_blocks entry must be a valid IPv4 CIDR block."
  }
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair installed for SSH. Changing it replaces the instance."
  default     = null
}

################################################################################
# Instance
################################################################################

variable "instance_type" {
  type        = string
  description = "EC2 instance type. Changing it stops and restarts the instance in place."

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9-]+$", var.instance_type))
    error_message = "The instance_type must be an EC2 instance type such as m7i.large."
  }
}

variable "operating_system" {
  type        = string
  description = "Base image when ami_id is not set: ubuntu-24.04 or al2023. The latest image for the instance type's architecture is used at creation; later image releases never replace the instance."
  default     = "ubuntu-24.04"

  validation {
    condition     = contains(["ubuntu-24.04", "al2023"], var.operating_system)
    error_message = "The operating_system must be ubuntu-24.04 or al2023."
  }
}

variable "ami_id" {
  type        = string
  description = "Custom AMI. Overrides operating_system. Setting or changing it replaces the instance and its root volume."
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "The ami_id must be an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB. Can be increased in place; it cannot be shrunk."
  default     = 100

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384 && floor(var.root_volume_size) == var.root_volume_size
    error_message = "The root_volume_size must be a whole number between 8 and 16384."
  }
}

variable "root_volume_type" {
  type        = string
  description = "Root volume type."
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume_type)
    error_message = "The root_volume_type must be gp3, gp2, io1, or io2."
  }
}

variable "root_volume_kms_key_id" {
  type        = string
  description = "KMS key ARN for root volume encryption. Defaults to the account's default EBS key. Changing it replaces the instance."
  default     = null
}

variable "user_data" {
  type        = string
  description = "Shell script run as root on the first boot only. Later changes are ignored so they never restart or replace the instance."
  default     = ""
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "Managed IAM policy ARNs attached to the instance role, in addition to Session Manager access."
  default     = []

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws(-[a-z]+)*:iam::(aws|[0-9]{12}):policy/.+$", arn))])
    error_message = "Every iam_policy_arns entry must be an IAM policy ARN."
  }
}

variable "ssm_enabled" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore so you can log in with Session Manager without opening ports."
  default     = true
}

variable "termination_protection_enabled" {
  type        = bool
  description = "Block terminating the instance through the EC2 API. Turn off before destroying the module."
  default     = false
}

################################################################################
# Auto stop
################################################################################

variable "auto_stop_enabled" {
  type        = bool
  description = "Stop the dev box on a schedule to save cost. Its disk is kept; start it again from the EC2 console or CLI."
  default     = false
}

variable "auto_stop_schedule_expression" {
  type        = string
  description = "EventBridge Scheduler cron() expression for auto stop, evaluated in auto_stop_timezone."
  default     = "cron(0 19 * * ? *)"

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.auto_stop_schedule_expression))
    error_message = "The auto_stop_schedule_expression must be an EventBridge Scheduler cron() expression, such as cron(0 19 * * ? *)."
  }
}

variable "auto_stop_timezone" {
  type        = string
  description = "IANA time zone for auto_stop_schedule_expression, such as America/New_York."
  default     = "UTC"

  validation {
    condition     = length(var.auto_stop_timezone) > 0
    error_message = "The auto_stop_timezone must not be empty."
  }
}
