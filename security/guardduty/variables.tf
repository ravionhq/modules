################################################################################
# Regions
################################################################################

variable "regions" {
  type        = list(string)
  description = "AWS Regions where Amazon GuardDuty is enabled. Every Region must be enabled (opted in) for the account; GuardDuty creates one detector per Region."

  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one Region is required."
  }

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "Every entry in regions must be an AWS Region code such as us-east-1 or eu-central-1."
  }

  validation {
    condition     = length(var.regions) == length(distinct(var.regions))
    error_message = "Regions must not contain duplicates."
  }
}

################################################################################
# Detector
################################################################################

variable "finding_publishing_frequency" {
  type        = string
  description = "How often GuardDuty exports updated findings to EventBridge and S3: FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS. New findings are always exported within five minutes."
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "The finding_publishing_frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

################################################################################
# Protection plans
#
# Every plan is managed explicitly (ENABLED or DISABLED) in every Region so the
# effective GuardDuty configuration is fully described by this module rather
# than by AWS account-level defaults or console trials.
################################################################################

variable "s3_protection_enabled" {
  type        = bool
  description = "Enable S3 Protection (S3_DATA_EVENTS): monitors S3 data-plane events for suspicious access to buckets and objects."
  default     = true
}

variable "eks_protection_enabled" {
  type        = bool
  description = "Enable EKS Protection (EKS_AUDIT_LOGS): monitors Kubernetes audit logs from EKS clusters."
  default     = true
}

variable "malware_protection_enabled" {
  type        = bool
  description = "Enable Malware Protection for EC2 (EBS_MALWARE_PROTECTION): scans EBS volumes attached to EC2 instances and container workloads when GuardDuty detects malicious behaviour."
  default     = true
}

variable "rds_protection_enabled" {
  type        = bool
  description = "Enable RDS Protection (RDS_LOGIN_EVENTS): monitors login activity to Aurora and supported RDS databases."
  default     = true
}

variable "lambda_protection_enabled" {
  type        = bool
  description = "Enable Lambda Protection (LAMBDA_NETWORK_LOGS): monitors Lambda network activity logs."
  default     = true
}

variable "runtime_monitoring_enabled" {
  type        = bool
  description = "Enable Runtime Monitoring (RUNTIME_MONITORING): OS-level threat detection for EKS, ECS Fargate, and EC2 workloads via the GuardDuty security agent. Disabled by default because it adds agent cost per workload."
  default     = false
}

variable "runtime_monitoring_automated_agents" {
  type        = list(string)
  description = "Workload types where GuardDuty installs and manages the Runtime Monitoring security agent automatically: EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT, EC2_AGENT_MANAGEMENT. Ignored unless runtime_monitoring_enabled is true."
  default     = ["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT"]

  validation {
    condition = alltrue([
      for agent in var.runtime_monitoring_automated_agents :
      contains(["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT"], agent)
    ])
    error_message = "Every entry in runtime_monitoring_automated_agents must be one of: EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT, EC2_AGENT_MANAGEMENT."
  }

  validation {
    condition     = length(var.runtime_monitoring_automated_agents) == length(distinct(var.runtime_monitoring_automated_agents))
    error_message = "The runtime_monitoring_automated_agents list must not contain duplicates."
  }
}

################################################################################
# Tags
################################################################################

variable "tags" {
  type        = map(string)
  description = "A map of additional tags applied to every GuardDuty detector."
  default     = {}
}
