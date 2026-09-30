################################################################################
# Grafana Workspace
################################################################################

resource "aws_grafana_workspace" "this" {
  name                     = var.name
  description              = var.description
  grafana_version          = var.grafana_version
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = [local.identity_center ? "AWS_SSO" : "SAML"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.this.arn

  configuration = jsonencode({
    plugins         = { pluginAdminEnabled = local.plugin_admin_enabled }
    unifiedAlerting = { enabled = true }
  })

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(local.missing_user_names) == 0
      error_message = "These IAM Identity Center users do not exist: ${join(", ", local.missing_user_names)}."
    }

    precondition {
      condition     = length(local.missing_group_names) == 0
      error_message = "These IAM Identity Center groups do not exist: ${join(", ", local.missing_group_names)}."
    }

    precondition {
      condition     = local.identity_center || try(trimspace(var.saml_idp_metadata_url), "") != "" || try(trimspace(var.saml_idp_metadata_xml), "") != ""
      error_message = "SAML sign-in needs the identity provider's metadata URL or metadata document."
    }

    precondition {
      condition     = (local.prometheus_query_url == null) == (local.prometheus_workspace_arn == null)
      error_message = "A Prometheus data source needs both the workspace's query URL and its ARN."
    }

    precondition {
      condition     = !local.prometheus_enabled || can(regex("^https://aps-workspaces\\.[a-z0-9-]+\\.amazonaws\\.com/workspaces/ws-[a-z0-9-]+$", local.prometheus_query_url))
      error_message = "The Prometheus query URL must be an Amazon Managed Service for Prometheus workspace endpoint, https://aps-workspaces.<region>.amazonaws.com/workspaces/<workspace id>."
    }
  }
}

resource "aws_grafana_role_association" "this" {
  for_each = local.role_associations

  workspace_id = aws_grafana_workspace.this.id
  role         = each.key
  user_ids     = each.value.user_ids
  group_ids    = each.value.group_ids
}

resource "aws_grafana_workspace_saml_configuration" "this" {
  count = local.identity_center ? 0 : 1

  workspace_id            = aws_grafana_workspace.this.id
  idp_metadata_url        = try(trimspace(var.saml_idp_metadata_url), "") == "" ? null : trimspace(var.saml_idp_metadata_url)
  idp_metadata_xml        = try(trimspace(var.saml_idp_metadata_xml), "") == "" ? null : var.saml_idp_metadata_xml
  role_assertion          = var.saml_role_assertion
  admin_role_values       = var.saml_admin_role_values
  editor_role_values      = var.saml_editor_role_values
  login_assertion         = var.saml_login_assertion
  email_assertion         = var.saml_email_assertion
  name_assertion          = var.saml_name_assertion
  org_assertion           = var.saml_org_assertion
  allowed_organizations   = var.saml_allowed_organizations
  login_validity_duration = var.saml_login_validity_minutes
}
