variable "ravion_id" {
  description = "Your AWS account's id in Ravion (from Ravion's connect dialog). Ravion's roles are named rvn-<ravion_id> and trust only tokens Ravion issues for it."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,40}$", var.ravion_id))
    error_message = "ravion_id is the id Ravion's connect dialog shows."
  }
}

variable "onboarding_token" {
  description = "Onboarding token from Ravion's connect dialog. Only sent to callback_url to report the setup back to Ravion; it grants nothing in your AWS account."
  type        = string
  sensitive   = true
}

variable "enable_deployments" {
  description = "Create the role Ravion uses to deploy your services (rvn-<ravion_id>-deployments)."
  type        = bool
  default     = true
}

variable "enable_terraform" {
  description = "Create the role Ravion uses for Terraform plan and apply steps (rvn-<ravion_id>-terraform). This is the only role that can give a step AdministratorAccess. Set to false if you do not use Terraform with Ravion."
  type        = bool
  default     = true
}

variable "enable_sandboxes" {
  description = "Create the role for CI pipelines, GitHub runners and sandboxes (rvn-<ravion_id>-sandboxes). It is also created when deployments or Terraform are enabled, since every pipeline step runs on a sandbox runner."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider for https://oidc.ravion.com in this account. An account holds one provider per issuer, so set this when another Ravion connection (or its CloudFormation stack) already created one. Empty creates it."
  type        = string
  default     = ""
}

variable "callback_url" {
  description = "Ravion endpoint the setup reports to."
  type        = string
  default     = "https://api.ravion.com/internal/aws-account/terraform-callback"

  validation {
    condition     = can(regex("^https://", var.callback_url)) || can(regex("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/", var.callback_url))
    error_message = "callback_url must be https:// (http:// is only accepted for localhost)."
  }
}

variable "send_callback" {
  description = "Report the setup to Ravion. Leave on: Ravion only uses the roles after the report, once it has checked it can assume them."
  type        = bool
  default     = true
}
