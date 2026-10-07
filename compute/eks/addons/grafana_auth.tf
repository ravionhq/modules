################################################################################
# In-cluster Grafana sign-in
#
# Grafana's own authentication, as Grafana's own configuration names it:
# username and password for local users, and the OAuth providers Grafana
# supports out of the box. Each grafana_auth_providers entry becomes one
# [auth.<provider>] section in grafana.ini.
#
# Every client secret is a Secrets Manager ARN. The External Secrets Operator
# materializes it into a Kubernetes Secret, and Grafana reads it from
# GF_AUTH_<PROVIDER>_CLIENT_SECRET: it is never a Helm value, a grafana.ini
# line or a Terraform output.
################################################################################

locals {
  grafana_auth_entries = var.grafana_enabled ? var.grafana_auth_providers : []

  # The validation guarantees each provider appears once.
  grafana_auth_by_provider = { for entry in local.grafana_auth_entries : entry.provider => entry }

  grafana_auth_values = {
    for provider, entry in local.grafana_auth_by_provider : provider => {
      client_id         = try(trimspace(entry.client_id), "")
      client_id_arn     = try(trimspace(entry.client_id_arn), "")
      client_secret_arn = try(trimspace(entry.client_secret_arn), "")
      base_url          = trimsuffix(try(trimspace(entry.url), ""), "/")
      tenant_id         = try(trimspace(entry.tenant_id), "")
    }
  }

  # Where to sign in. Entra ID and Okta derive it from the tenant and the org
  # URL, a self-managed GitLab from its URL, and a generic provider names it
  # outright; Google, GitHub and gitlab.com keep Grafana's defaults.
  grafana_auth_endpoints = {
    for provider, entry in local.grafana_auth_by_provider : provider => (
      provider == "azuread" ? {
        auth_url  = "https://login.microsoftonline.com/${local.grafana_auth_values[provider].tenant_id}/oauth2/v2.0/authorize"
        token_url = "https://login.microsoftonline.com/${local.grafana_auth_values[provider].tenant_id}/oauth2/v2.0/token"
        api_url   = ""
        } : provider == "okta" ? {
        auth_url  = "${local.grafana_auth_values[provider].base_url}/oauth2/v1/authorize"
        token_url = "${local.grafana_auth_values[provider].base_url}/oauth2/v1/token"
        api_url   = "${local.grafana_auth_values[provider].base_url}/oauth2/v1/userinfo"
        } : provider == "gitlab" && local.grafana_auth_values[provider].base_url != "" ? {
        auth_url  = "${local.grafana_auth_values[provider].base_url}/oauth/authorize"
        token_url = "${local.grafana_auth_values[provider].base_url}/oauth/token"
        api_url   = "${local.grafana_auth_values[provider].base_url}/api/v4"
        } : provider == "generic_oauth" ? {
        auth_url  = try(trimspace(entry.auth_url), "")
        token_url = try(trimspace(entry.token_url), "")
        api_url   = try(trimspace(entry.api_url), "")
        } : {
        auth_url  = ""
        token_url = ""
        api_url   = ""
      }
    )
  }

  # Lists go in as JSON arrays, which Grafana accepts for every list setting
  # and which keeps an organization name with a space in it whole.
  grafana_auth_lists = {
    for provider, entry in local.grafana_auth_by_provider : provider => {
      for key, values in {
        allowed_domains       = entry.allowed_domains
        allowed_groups        = entry.allowed_groups
        allowed_organizations = entry.allowed_organizations
        team_ids              = entry.team_ids
      } : key => [for value in values : trimspace(value) if trimspace(value) != ""]
    }
  }

  # One [auth.<provider>] section per entry: what is set, under Grafana's key
  # names, then the entry's own settings map, verbatim.
  grafana_auth_ini = {
    for provider, entry in local.grafana_auth_by_provider : "auth.${provider}" => merge(
      {
        enabled = true
      },
      {
        for key, value in merge(
          {
            # Absent when read from Secrets Manager, through GF_AUTH_<PROVIDER>_CLIENT_ID.
            client_id           = local.grafana_auth_values[provider].client_id
            name                = try(trimspace(entry.name), "")
            scopes              = try(trimspace(entry.scopes), "")
            role_attribute_path = try(trimspace(entry.role_attribute_path), "")
          },
          local.grafana_auth_endpoints[provider],
          { for key, values in local.grafana_auth_lists[provider] : key => length(values) > 0 ? jsonencode(values) : "" },
        ) : key => value if value != ""
      },
      entry.settings,
    )
  }

  grafana_auth_secret_names = {
    for provider in keys(local.grafana_auth_by_provider) : provider => "ravion-grafana-${replace(provider, "_", "-")}-oauth"
  }

  grafana_auth_secrets = [
    for provider in keys(local.grafana_auth_by_provider) : {
      name      = local.grafana_auth_secret_names[provider]
      namespace = local.grafana_namespace
      template  = {}
      data = concat(
        [{
          secretKey = "clientSecret"
          remoteRef = local.grafana_auth_values[provider].client_secret_arn
        }],
        [for arn in [local.grafana_auth_values[provider].client_id_arn] : {
          secretKey = "clientId"
          remoteRef = arn
        } if arn != ""],
      )
    }
  ]

  # Grafana reads any setting from GF_<SECTION>_<KEY>.
  grafana_env_value_from = merge(
    {
      for provider in keys(local.grafana_auth_by_provider) : "GF_AUTH_${upper(provider)}_CLIENT_SECRET" => {
        secretKeyRef = {
          name = local.grafana_auth_secret_names[provider]
          key  = "clientSecret"
        }
      }
    },
    {
      for provider, value in local.grafana_auth_values : "GF_AUTH_${upper(provider)}_CLIENT_ID" => {
        secretKeyRef = {
          name = local.grafana_auth_secret_names[provider]
          key  = "clientId"
        }
      } if value.client_id_arn != ""
    },
  )

  # grafana.ini: SigV4 for the AMP data source always; the role new accounts
  # get; the external URL OAuth providers redirect back to while grafana_access
  # serves Grafana; and the sign-in methods. Turning username and password
  # off removes the login form and HTTP basic auth both, so a password is
  # accepted nowhere.
  grafana_ini = merge(
    {
      auth = merge(
        { sigv4_auth_enabled = true },
        var.grafana_auth.login_form_enabled ? {} : { disable_login_form = true },
      )
      users = {
        auto_assign_org_role = var.grafana_auth.default_role
      }
    },
    { for section, settings in { "auth.basic" = { enabled = false } } : section => settings if !var.grafana_auth.login_form_enabled },
    local.grafana_access_enabled ? {
      server = {
        domain   = local.grafana_hostname
        root_url = "https://${local.grafana_hostname}"
      }
    } : {},
    local.grafana_auth_ini,
  )

  # Google, GitHub and gitlab.com sign in anyone who has an account there, so
  # each needs one of the restrictions Grafana applies to that provider. Entra
  # ID, Okta, self-managed GitLab and a generic provider sign in only the
  # identity provider's own users.
  grafana_auth_restrictions = {
    google = ["allowed_domains", "allowed_groups"]
    github = ["allowed_organizations", "team_ids", "allowed_domains"]
    gitlab = ["allowed_groups", "allowed_domains"]
  }

  grafana_auth_unrestricted = [
    for provider, lists in local.grafana_auth_lists : provider
    if contains(keys(local.grafana_auth_restrictions), provider) && !(provider == "gitlab" && local.grafana_auth_values[provider].base_url != "") && alltrue([for key in local.grafana_auth_restrictions[provider] : length(lists[key]) == 0])
  ]

  grafana_auth_without_client = [
    for provider, value in local.grafana_auth_values : provider
    if(value.client_id == "" && value.client_id_arn == "") || value.client_secret_arn == ""
  ]

  grafana_auth_client_id_twice = [
    for provider, value in local.grafana_auth_values : provider
    if value.client_id != "" && value.client_id_arn != ""
  ]

  grafana_auth_without_endpoint = [
    for provider, value in local.grafana_auth_values : provider if(
      (provider == "azuread" && value.tenant_id == "") ||
      (provider == "okta" && value.base_url == "") ||
      (provider == "generic_oauth" && (local.grafana_auth_endpoints[provider].auth_url == "" || local.grafana_auth_endpoints[provider].token_url == ""))
    )
  ]

  # Grafana asks Google for a user's Workspace groups only when the scopes
  # include the Cloud Identity groups scope. Without it, allowed_groups admits
  # nobody and a role mapping over groups falls back to the default role.
  grafana_google_groups_scope = "https://www.googleapis.com/auth/cloud-identity.groups.readonly"

  grafana_auth_google_groups_without_scope = [
    for provider, entry in local.grafana_auth_by_provider : provider
    if provider == "google" && (
      length(local.grafana_auth_lists[provider].allowed_groups) > 0 ||
      strcontains(try(trimspace(entry.role_attribute_path), ""), "groups")
    ) && !contains(split(" ", replace(try(trimspace(entry.scopes), ""), ",", " ")), local.grafana_google_groups_scope)
  ]

  # settings carries the keys the module does not, so it can neither switch a
  # provider, hold a secret, nor quietly undo a restriction the checks read.
  grafana_auth_managed_keys = [
    "enabled", "client_id", "client_secret", "name", "scopes", "role_attribute_path",
    "auth_url", "token_url", "api_url",
    "allowed_domains", "allowed_groups", "allowed_organizations", "team_ids",
  ]

  grafana_auth_settings_overlapping = [
    for provider, entry in local.grafana_auth_by_provider : provider
    if length(setintersection(keys(entry.settings), local.grafana_auth_managed_keys)) > 0
  ]
}
