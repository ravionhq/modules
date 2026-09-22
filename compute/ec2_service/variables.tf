################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

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

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the instances run."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the Auto Scaling Group instances."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "public_ip_assignment_enabled" {
  type        = bool
  description = "Assign public IPs to instances. Use when instances run in public subnets without NAT egress."
  default     = false
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs attached to the instances."
  default     = []

  validation {
    condition     = alltrue([for sg in var.additional_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All additional_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "direct_access_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach the app port directly, in addition to the load balancer."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.direct_access_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All direct_access_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

################################################################################
# Runtime
################################################################################

variable "runtime" {
  type        = string
  description = "How the app is deployed on the instances. 'container' swaps a Docker container through the module's SSM deploy document; 'manual' means the deploy manager runs a user-provided list of shell commands on each instance."

  validation {
    condition     = contains(["container", "manual"], var.runtime)
    error_message = "The runtime must be 'container' or 'manual'."
  }
}

variable "docker_socket_mount_enabled" {
  type        = bool
  description = "Mount the host Docker socket into the container and add the host docker group's GID. This grants the container root-equivalent control of the instance: it can start privileged containers, read the host filesystem, and use the instance role. Only meaningful for the container runtime."
  default     = false

  validation {
    condition     = !var.docker_socket_mount_enabled || var.runtime == "container"
    error_message = "The docker_socket_mount_enabled can only be true when runtime is 'container'."
  }
}

variable "app_port" {
  type        = number
  description = "Port the app listens on. Required when a load balancer is attached or a local health check path is set."
  default     = null

  validation {
    condition     = var.app_port == null || (var.app_port >= 1 && var.app_port <= 65535)
    error_message = "The app_port must be between 1 and 65535."
  }
}

variable "container_start_command" {
  type        = string
  description = "Optional command for the container runtime that overrides the image default command."
  default     = null
}

variable "manual_start_command" {
  type        = string
  description = "Long-running foreground application command managed and restarted by supervisord in the manual runtime. Deploy commands prepare each release; this command starts it."
  default     = null

  validation {
    condition     = var.runtime != "manual" || (var.manual_start_command != null && length(trimspace(var.manual_start_command)) > 0)
    error_message = "The manual_start_command must be set when runtime is 'manual'."
  }
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Plain environment variables written to the app environment file at deploy time."
  default     = []
}

variable "secrets" {
  type = list(object({
    name       = string
    value_from = string
  }))
  description = "Secret environment variables fetched on the instance and appended to the app environment file on every deploy (and at instance boot for manual). value_from is a Secrets Manager secret ARN, an SSM parameter ARN, or a bare SSM parameter name. Multi-line secret values are not supported (env-file format)."
  default     = []

  validation {
    condition     = alltrue([for s in var.secrets : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", s.name))])
    error_message = "Each secret name must be a valid environment variable name."
  }
}

variable "deploy_health_check_path" {
  type        = string
  description = "Local HTTP path polled on the instance after each deploy to gate success, such as /health. Requires app_port. Null disables the local health gate."
  default     = null

  validation {
    condition     = var.deploy_health_check_path == null || can(regex("^/", var.deploy_health_check_path))
    error_message = "The deploy_health_check_path must be an absolute path starting with '/'."
  }
}

variable "deploy_timeout_seconds" {
  type        = number
  description = "Timeout in seconds for the deploy document's script on each instance."
  default     = 1200

  validation {
    condition     = var.deploy_timeout_seconds >= 60 && var.deploy_timeout_seconds <= 14400
    error_message = "The deploy_timeout_seconds must be between 60 and 14400."
  }
}

################################################################################
# Instances
################################################################################

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the Auto Scaling Group. Use the newest generation the region offers for the chosen family, such as m8g rather than m7g or m6i; Graviton (g) types need an arm64 image. See the module README for the selection guide."
}

variable "ami_id" {
  type        = string
  description = "Custom AMI for the instances. Leave null to use the latest Amazon Linux 2023 AMI. Custom AMIs must run cloud-init and include the SSM agent."
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-", var.ami_id))
    error_message = "The ami_id must be a valid AMI ID starting with 'ami-'."
  }
}

variable "key_name" {
  type        = string
  description = "Key pair name for SSH access to the instances."
  default     = null
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB."
  default     = 30

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "The root_volume_size must be between 8 and 16384 GB."
  }
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS volume type."
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume_type)
    error_message = "The root_volume_type must be 'gp3', 'gp2', 'io1', or 'io2'."
  }
}

variable "data_volume_creation_enabled" {
  type        = bool
  description = "Attach a dedicated data EBS volume to each instance, formatted and mounted on first boot. Data survives in-place deploys but not instance termination."
  default     = false
}

variable "data_volume_size" {
  type        = number
  description = "Data EBS volume size in GB."
  default     = 20

  validation {
    condition     = var.data_volume_size >= 1 && var.data_volume_size <= 16384
    error_message = "The data_volume_size must be between 1 and 16384 GB."
  }
}

variable "data_volume_type" {
  type        = string
  description = "Data EBS volume type."
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.data_volume_type)
    error_message = "The data_volume_type must be 'gp3', 'gp2', 'io1', or 'io2'."
  }
}

variable "data_volume_mount_path" {
  type        = string
  description = "Host path where the data volume is mounted. Container apps see it at the same path."
  default     = "/data"

  validation {
    condition     = can(regex("^/", var.data_volume_mount_path))
    error_message = "The data_volume_mount_path must be an absolute path starting with '/'."
  }
}

variable "additional_user_data" {
  type        = string
  description = "Additional shell script appended to the instance bootstrap user data."
  default     = ""
}

################################################################################
# Auto Scaling Group
################################################################################

variable "min_size" {
  type        = number
  description = "Minimum instances in the Auto Scaling Group."
  default     = 1

  validation {
    condition     = var.min_size >= 0
    error_message = "The min_size must be at least 0."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum instances in the Auto Scaling Group."
  default     = 1

  validation {
    condition     = var.max_size >= 1
    error_message = "The max_size must be at least 1."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Desired instances in the Auto Scaling Group. Null lets the group manage it within min/max."
  default     = null
}

variable "health_check_type" {
  type        = string
  description = "ASG health check type. 'EC2' replaces instances only on instance failure. 'ELB' also replaces instances failing load balancer health checks; note that in-place deploys briefly deregister instances, so prefer 'EC2' unless deploys are infrequent."
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "The health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  type        = number
  description = "Seconds after launch before ASG health checks apply."
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "The health_check_grace_period must be 0 or greater."
  }
}

variable "cpu_autoscaling_enabled" {
  type        = bool
  description = "Scale the group to maintain the target average CPU utilization."
  default     = false
}

variable "cpu_target_value" {
  type        = number
  description = "Average CPU utilization target for target tracking scaling."
  default     = 70

  validation {
    condition     = var.cpu_target_value >= 1 && var.cpu_target_value <= 100
    error_message = "The cpu_target_value must be between 1 and 100."
  }
}

################################################################################
# Load Balancer Attachment
################################################################################

variable "load_balancer_attachment" {
  type = object({
    creation_enabled = optional(bool, true)

    target_group = object({
      port                 = number
      deregistration_delay = optional(number, 30)
      slow_start           = optional(number, 0)

      health_check = optional(object({
        enabled             = optional(bool, true)
        path                = optional(string, "/")
        port                = optional(string, "traffic-port")
        matcher             = optional(string, "200-399")
        interval            = optional(number, 30)
        timeout             = optional(number, 5)
        healthy_threshold   = optional(number, 3)
        unhealthy_threshold = optional(number, 3)
      }), {})

      stickiness = optional(object({
        enabled         = optional(bool, false)
        type            = optional(string, "lb_cookie")
        cookie_duration = optional(number, 86400)
        cookie_name     = optional(string, null)
      }), null)
    })

    listener_rules = optional(list(object({
      listener_arn = string
      priority     = optional(number, null)

      conditions = list(object({
        type   = string
        values = list(string)
      }))
    })), [])
  })
  description = "Application Load Balancer attachment: an instance target group plus listener rules on an existing ALB listener. Null runs the group without a load balancer (worker mode)."
  default     = null

  validation {
    condition = try(
      var.load_balancer_attachment.target_group.slow_start == 0 || (
        var.load_balancer_attachment.target_group.slow_start >= 30 &&
        var.load_balancer_attachment.target_group.slow_start <= 900
      ),
      true
    )
    error_message = "The target group slow_start must be 0 or between 30 and 900 seconds."
  }

  validation {
    condition = try(
      var.load_balancer_attachment.target_group.stickiness == null ||
      contains(["lb_cookie", "app_cookie"], var.load_balancer_attachment.target_group.stickiness.type),
      true
    )
    error_message = "The target group stickiness type must be 'lb_cookie' or 'app_cookie'."
  }

  validation {
    condition = try(
      var.load_balancer_attachment.target_group.stickiness == null ||
      !var.load_balancer_attachment.target_group.stickiness.enabled ||
      var.load_balancer_attachment.target_group.stickiness.type != "app_cookie" ||
      length(trimspace(coalesce(var.load_balancer_attachment.target_group.stickiness.cookie_name, ""))) > 0,
      true
    )
    error_message = "The target group stickiness cookie_name is required for app_cookie stickiness."
  }

  validation {
    condition = try(
      var.load_balancer_attachment.target_group.stickiness == null || (
        var.load_balancer_attachment.target_group.stickiness.cookie_duration >= 1 &&
        var.load_balancer_attachment.target_group.stickiness.cookie_duration <= 604800
      ),
      true
    )
    error_message = "The target group stickiness cookie_duration must be between 1 and 604800 seconds."
  }
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group of the load balancer, allowed to reach the app port on the instances."
  default     = null

  validation {
    condition     = var.load_balancer_security_group_id == null || can(regex("^sg-", var.load_balancer_security_group_id))
    error_message = "The load_balancer_security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

################################################################################
# EFS
################################################################################

variable "efs_enabled" {
  type        = bool
  description = "Mount an EFS file system on every instance."
  default     = false
}

variable "efs_file_system_id" {
  type        = string
  description = "EFS file system ID to mount. Required when efs_enabled is true."
  default     = null
}

variable "efs_access_point_id" {
  type        = string
  description = "EFS access point to mount through, when set."
  default     = null
}

variable "efs_client_security_group_id" {
  type        = string
  description = "EFS client security group attached to the instances so NFS traffic is allowed."
  default     = null

  validation {
    condition     = var.efs_client_security_group_id == null || can(regex("^sg-", var.efs_client_security_group_id))
    error_message = "The efs_client_security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "efs_mount_path" {
  type        = string
  description = "Host path where the EFS file system is mounted."
  default     = "/mnt/efs"

  validation {
    condition     = can(regex("^/", var.efs_mount_path))
    error_message = "The efs_mount_path must be an absolute path starting with '/'."
  }
}

################################################################################
# Artifact Stores
################################################################################

variable "ecr_repository_creation_enabled" {
  type        = bool
  description = "Create an ECR repository for images built for this service. Used by the container runtime."
  default     = false
}

variable "ecr_force_deletion_enabled" {
  type        = bool
  description = "Allow deleting the ECR repository even when it contains images."
  default     = false
}

variable "ecr_scan_on_push_enabled" {
  type        = bool
  description = "Scan images for vulnerabilities after they are pushed to the ECR repository."
  default     = true
}

################################################################################
# Logging
################################################################################

variable "log_retention_in_days" {
  type        = number
  description = "CloudWatch log retention for app logs."
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 1
    error_message = "The log_retention_in_days must be at least 1."
  }
}

variable "log_rotation_max_size_mb" {
  type        = number
  description = "Maximum size of the on-instance app log file before supervisord rotates it. Bounds disk usage when a process restarts repeatedly."
  default     = 20

  validation {
    condition     = var.log_rotation_max_size_mb == floor(var.log_rotation_max_size_mb) && var.log_rotation_max_size_mb >= 1 && var.log_rotation_max_size_mb <= 1024
    error_message = "The log_rotation_max_size_mb must be a whole number between 1 and 1024."
  }
}

variable "log_rotation_backup_count" {
  type        = number
  description = "Number of rotated app log files supervisord keeps on the instance. Total on-instance app log usage is bounded by (backups + 1) * log_rotation_max_size_mb."
  default     = 5

  validation {
    condition     = var.log_rotation_backup_count == floor(var.log_rotation_backup_count) && var.log_rotation_backup_count >= 1 && var.log_rotation_backup_count <= 100
    error_message = "The log_rotation_backup_count must be a whole number between 1 and 100."
  }
}
