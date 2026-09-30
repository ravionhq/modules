################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name of the Grafana workspace, and the prefix of the IAM role and service account this module creates."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._~-]{0,54}$", var.name))
    error_message = "The name must be 1-55 letters, digits, periods, underscores, tildes or hyphens, starting with a letter or digit."
  }
}

variable "description" {
  type        = string
  description = "Description of the Grafana workspace."
  default     = null
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources."
  default     = {}
}

################################################################################
# Workspace
################################################################################

variable "grafana_version" {
  type        = string
  description = "Grafana version of the workspace, one of the versions Amazon Managed Grafana offers. Changing it upgrades the workspace in place; AWS does not allow downgrades."
  default     = "12.4"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.grafana_version))
    error_message = "The grafana_version must be a major.minor version such as 12.4."
  }
}

variable "plugin_admin_enabled" {
  type        = bool
  description = "Let workspace admins install, update and remove plugins from the Grafana plugin catalog. Always on while xray_enabled is true: the X-Ray data source is a catalog plugin, which Amazon Managed Grafana installs only while plugin management is on."
  default     = false
  nullable    = false
}

################################################################################
# Sign-in
################################################################################

variable "authentication" {
  type        = string
  description = "How users sign in: iam_identity_center, through the organization's IAM Identity Center; or saml, through a SAML 2.0 identity provider."
  default     = "iam_identity_center"
  nullable    = false

  validation {
    condition     = contains(["iam_identity_center", "saml"], var.authentication)
    error_message = "The authentication must be iam_identity_center or saml."
  }
}

variable "identity_center_region" {
  type        = string
  description = "Region of the organization's IAM Identity Center instance, where user and group names are looked up. Null uses the workspace's region."
  default     = null
}

variable "admin_user_names" {
  type        = list(string)
  description = "IAM Identity Center user names granted the Grafana Admin role."
  default     = []
  nullable    = false
}

variable "editor_user_names" {
  type        = list(string)
  description = "IAM Identity Center user names granted the Grafana Editor role."
  default     = []
  nullable    = false
}

variable "viewer_user_names" {
  type        = list(string)
  description = "IAM Identity Center user names granted the Grafana Viewer role."
  default     = []
  nullable    = false
}

variable "admin_group_names" {
  type        = list(string)
  description = "IAM Identity Center group display names whose members are granted the Grafana Admin role."
  default     = []
  nullable    = false
}

variable "editor_group_names" {
  type        = list(string)
  description = "IAM Identity Center group display names whose members are granted the Grafana Editor role."
  default     = []
  nullable    = false
}

variable "viewer_group_names" {
  type        = list(string)
  description = "IAM Identity Center group display names whose members are granted the Grafana Viewer role."
  default     = []
  nullable    = false
}

variable "saml_idp_metadata_url" {
  type        = string
  description = "URL of the SAML identity provider's metadata. Set this or saml_idp_metadata_xml when authentication is saml."
  default     = null
}

variable "saml_idp_metadata_xml" {
  type        = string
  description = "The SAML identity provider's metadata document. Set this or saml_idp_metadata_url when authentication is saml."
  default     = null
}

variable "saml_role_assertion" {
  type        = string
  description = "SAML assertion attribute that carries the user's roles, matched against saml_admin_role_values and saml_editor_role_values."
  default     = "role"
  nullable    = false
}

variable "saml_admin_role_values" {
  type        = list(string)
  description = "Role values that grant the Grafana Admin role."
  default     = []
  nullable    = false
}

variable "saml_editor_role_values" {
  type        = list(string)
  description = "Role values that grant the Grafana Editor role. Everyone else is a Viewer."
  default     = []
  nullable    = false
}

variable "saml_login_assertion" {
  type        = string
  description = "SAML assertion attribute used as the user's Grafana login. Null uses the identity provider's default."
  default     = null
}

variable "saml_email_assertion" {
  type        = string
  description = "SAML assertion attribute used as the user's email. Null uses the identity provider's default."
  default     = null
}

variable "saml_name_assertion" {
  type        = string
  description = "SAML assertion attribute used as the user's display name. Null uses the identity provider's default."
  default     = null
}

variable "saml_allowed_organizations" {
  type        = list(string)
  description = "Identity provider organizations whose users may sign in. Empty allows every user the identity provider signs in."
  default     = []
  nullable    = false
}

variable "saml_org_assertion" {
  type        = string
  description = "SAML assertion attribute that carries the user's organization, matched against saml_allowed_organizations."
  default     = null
}

variable "saml_login_validity_minutes" {
  type        = number
  description = "Minutes a SAML sign-in stays valid."
  default     = 1440
  nullable    = false
}

################################################################################
# Data sources
################################################################################

variable "data_source_region" {
  type        = string
  description = "Region the X-Ray and CloudWatch data sources query by default. Null uses the workspace's region."
  default     = null
}

variable "xray_enabled" {
  type        = bool
  description = "Add an AWS X-Ray data source and let the workspace read traces."
  default     = true
  nullable    = false
}

variable "cloudwatch_enabled" {
  type        = bool
  description = "Add a CloudWatch data source and let the workspace read CloudWatch metrics and logs."
  default     = true
  nullable    = false
}

variable "cloudwatch_default_log_group_names" {
  type        = list(string)
  description = "Log groups the CloudWatch data source selects by default in log queries."
  default     = []
  nullable    = false
}

variable "prometheus_query_url" {
  type        = string
  description = "Query URL of an Amazon Managed Service for Prometheus workspace to add as a data source. Null adds none."
  default     = null
}

variable "prometheus_workspace_arn" {
  type        = string
  description = "ARN of the Prometheus workspace behind prometheus_query_url. The workspace may read metrics from this Prometheus workspace only."
  default     = null
}
