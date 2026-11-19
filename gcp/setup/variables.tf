variable "project_id" {
  description = "ID of the Google Cloud project to connect to Ravion."
  type        = string
}

variable "ravion_account_id" {
  description = "The Ravion connection id (gcpact_...) shown in Ravion's connect dialog. The workload identity provider only accepts tokens Ravion minted for this connection."
  type        = string

  validation {
    condition     = can(regex("^gcpact_[A-Za-z0-9]+$", var.ravion_account_id))
    error_message = "ravion_account_id must be the gcpact_... id from Ravion."
  }
}

variable "onboarding_token" {
  description = "One-time onboarding token from Ravion's connect dialog. Only sent to callback_url to report the setup back; never stored in the project."
  type        = string
  sensitive   = true
}

variable "issuer_uri" {
  description = "Ravion's OIDC issuer. Leave the default unless Ravion support gives you another issuer (staging/dev)."
  type        = string
  default     = "https://oidc.ravion.com"

  validation {
    condition     = can(regex("^https://[^/]+(/.*)?$", var.issuer_uri))
    error_message = "issuer_uri must be an https:// URL."
  }
}

variable "callback_url" {
  description = "Ravion endpoint the setup reports to when it finishes."
  type        = string
  default     = "https://api.ravion.com/internal/gcp-account/callback"

  validation {
    condition     = can(regex("^https://", var.callback_url)) || can(regex("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/", var.callback_url))
    error_message = "callback_url must be https:// (http:// is only accepted for localhost)."
  }
}

variable "send_callback" {
  description = "Report the setup to Ravion at the end of apply. Turn off to review the plan without contacting Ravion."
  type        = bool
  default     = true
}

variable "pool_id" {
  description = "Workload identity pool id. Deleted pools are kept for 30 days and their ids cannot be reused in that time, so pick a new id when reinstalling after a destroy."
  type        = string
  default     = "ravion"

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.pool_id)) && !startswith(var.pool_id, "gcp-")
    error_message = "pool_id must be 4-32 lowercase letters, digits or hyphens and must not start with gcp-."
  }
}

variable "provider_id" {
  description = "Workload identity provider id. Defaults to ravion-<connection id>."
  type        = string
  default     = null

  validation {
    condition     = var.provider_id == null || (can(regex("^[a-z0-9-]{4,32}$", coalesce(var.provider_id, "xxxx"))) && !startswith(coalesce(var.provider_id, "x"), "gcp-"))
    error_message = "provider_id must be 4-32 lowercase letters, digits or hyphens and must not start with gcp-."
  }
}

variable "runner_sa_roles" {
  description = <<-EOT
    Project roles of ravion-runner, the service account attached to the VMs that run your pipeline
    steps and Terraform applies. The default, roles/editor, mirrors Ravion's AWS setup, where applies
    run with AdministratorAccess: Terraform can then create whatever your modules declare. Narrow it
    to the roles your infrastructure needs (for example roles/compute.admin, roles/storage.admin) if
    you prefer; applies that need more will fail with permission errors. roles/editor cannot change
    IAM policies, so modules that manage IAM also need roles/resourcemanager.projectIamAdmin.
  EOT
  type        = list(string)
  default     = ["roles/editor"]
}

variable "sandbox_host_sa_roles" {
  description = "Project roles of ravion-sandbox-host, the service account sandbox hosts run as. Bucket access is granted per sandbox pool, not here."
  type        = list(string)
  default     = ["roles/logging.logWriter", "roles/monitoring.metricWriter"]
}

variable "allowed_callers" {
  description = "Ravion services allowed to exchange tokens (the rvn:caller_service claim). api is the Ravion API, automations the workers that run deployments."
  type        = list(string)
  default     = ["api", "automations"]
}

variable "enable_apis" {
  description = "Enable the Google Cloud APIs Ravion uses. Turn off if your organization enables APIs centrally."
  type        = bool
  default     = true
}

variable "apis" {
  description = "APIs enabled when enable_apis is true."
  type        = list(string)
  default = [
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
}
