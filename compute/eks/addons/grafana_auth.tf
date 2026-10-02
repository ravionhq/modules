################################################################################
# In-cluster Grafana sign-in
#
# Grafana's own authentication, as Grafana's own configuration names it:
# username and password for local users, and the OAuth providers Grafana
# supports out of the box, each its own [auth.<provider>] section in
# grafana.ini. grafana_auth_providers selects the providers, one config object
# per provider carries their settings, the same shape as logs_providers and
# metrics_providers.
#
# Every client secret is a Secrets Manager ARN. The External Secrets Operator
# materializes it into a Kubernetes Secret, and Grafana reads it from
# GF_AUTH_<PROVIDER>_CLIENT_SECRET: it is never a Helm value, a grafana.ini
# line or a Terraform output.
################################################################################

locals {
  grafana_auth_providers = var.grafana_enabled ? distinct(var.grafana_auth_providers) : []

  grafana_auth_config = {
    google        = var.grafana_auth_google
    github        = var.grafana_auth_github
    gitlab        = var.grafana_auth_gitlab
    azuread       = var.grafana_auth_azuread
    okta          = var.grafana_auth_okta
    generic_oauth = var.grafana_auth_generic_oauth
  }

  grafana_gitlab_url = trimsuffix(try(trimspace(var.grafana_auth_gitlab.url), ""), "/")
  grafana_okta_url   = trimsuffix(try(trimspace(var.grafana_auth_okta.url), ""), "/")
  grafana_tenant_id  = try(trimspace(var.grafana_auth_azuread.tenant_id), "")

  # Settings under Grafana's own key names. Lists go in as JSON arrays, which
  # Grafana accepts for every list setting and which keeps an organization
  # name with a space in it whole.
  grafana_auth_settings = {
    google = {
      allowed_domains     = local.grafana_auth_list.google.allowed_domains
      allowed_groups      = local.grafana_auth_list.google.allowed_groups
      role_attribute_path = try(trimspace(var.grafana_auth_google.role_attribute_path), "")
    }
    github = {
      allowed_organizations = local.grafana_auth_list.github.allowed_organizations
      team_ids              = local.grafana_auth_list.github.team_ids
      role_attribute_path   = try(trimspace(var.grafana_auth_github.role_attribute_path), "")
    }
    gitlab = {
      auth_url            = local.grafana_gitlab_url == "" ? "" : "${local.grafana_gitlab_url}/oauth/authorize"
      token_url           = local.grafana_gitlab_url == "" ? "" : "${local.grafana_gitlab_url}/oauth/token"
      api_url             = local.grafana_gitlab_url == "" ? "" : "${local.grafana_gitlab_url}/api/v4"
      allowed_groups      = local.grafana_auth_list.gitlab.allowed_groups
      role_attribute_path = try(trimspace(var.grafana_auth_gitlab.role_attribute_path), "")
    }
    azuread = {
      auth_url       = "https://login.microsoftonline.com/${local.grafana_tenant_id}/oauth2/v2.0/authorize"
      token_url      = "https://login.microsoftonline.com/${local.grafana_tenant_id}/oauth2/v2.0/token"
      allowed_groups = local.grafana_auth_list.azuread.allowed_groups
    }
    okta = {
      auth_url            = "${local.grafana_okta_url}/oauth2/v1/authorize"
      token_url           = "${local.grafana_okta_url}/oauth2/v1/token"
      api_url             = "${local.grafana_okta_url}/oauth2/v1/userinfo"
      allowed_groups      = local.grafana_auth_list.okta.allowed_groups
      role_attribute_path = try(trimspace(var.grafana_auth_okta.role_attribute_path), "")
    }
    generic_oauth = {
      name                = try(trimspace(var.grafana_auth_generic_oauth.name), "")
      auth_url            = try(trimspace(var.grafana_auth_generic_oauth.auth_url), "")
      token_url           = try(trimspace(var.grafana_auth_generic_oauth.token_url), "")
      api_url             = try(trimspace(var.grafana_auth_generic_oauth.api_url), "")
      scopes              = try(trimspace(var.grafana_auth_generic_oauth.scopes), "")
      allowed_domains     = local.grafana_auth_list.generic_oauth.allowed_domains
      allowed_groups      = local.grafana_auth_list.generic_oauth.allowed_groups
      role_attribute_path = try(trimspace(var.grafana_auth_generic_oauth.role_attribute_path), "")
    }
  }

  grafana_auth_list = {
    for provider, config in local.grafana_auth_config : provider => {
      for key in ["allowed_domains", "allowed_groups", "allowed_organizations", "team_ids"] : key => (
        length(local.grafana_auth_trimmed[provider][key]) > 0 ? jsonencode(local.grafana_auth_trimmed[provider][key]) : ""
      )
    }
  }

  grafana_auth_trimmed = {
    for provider, config in local.grafana_auth_config : provider => {
      for key in ["allowed_domains", "allowed_groups", "allowed_organizations", "team_ids"] : key => [
        for value in try(config[key], []) : trimspace(value) if trimspace(value) != ""
      ]
    }
  }

  # One [auth.<provider>] section per selected provider: the typed settings
  # that are set, then the provider's own settings map, verbatim.
  grafana_auth_ini = {
    for provider in local.grafana_auth_providers : "auth.${provider}" => merge(
      {
        enabled   = true
        client_id = try(trimspace(local.grafana_auth_config[provider].client_id), "")
      },
      { for key, value in local.grafana_auth_settings[provider] : key => value if value != "" },
      local.grafana_auth_config[provider].settings,
    )
  }

  grafana_auth_secret_names = {
    for provider in local.grafana_auth_providers : provider => "ravion-grafana-${replace(provider, "_", "-")}-oauth"
  }

  grafana_auth_secrets = [
    for provider in local.grafana_auth_providers : {
      name      = local.grafana_auth_secret_names[provider]
      namespace = local.grafana_namespace
      template  = {}
      data = [{
        secretKey = "clientSecret"
        remoteRef = try(trimspace(local.grafana_auth_config[provider].client_secret_arn), "")
      }]
    }
  ]

  # Grafana reads any setting from GF_<SECTION>_<KEY>.
  grafana_env_value_from = {
    for provider in local.grafana_auth_providers : "GF_AUTH_${upper(provider)}_CLIENT_SECRET" => {
      secretKeyRef = {
        name = local.grafana_auth_secret_names[provider]
        key  = "clientSecret"
      }
    }
  }

  # grafana.ini: SigV4 for the AMP data source always; the role new accounts
  # get; the external URL OAuth providers redirect back to while Grafana is on
  # a load balancer; and the sign-in methods. Turning username and password
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
  # each needs a restriction. Entra ID, Okta, self-managed GitLab and a generic
  # provider sign in only the identity provider's own users.
  grafana_auth_unrestricted = [
    for provider in local.grafana_auth_providers : provider if(
      (provider == "google" && local.grafana_auth_list.google.allowed_domains == "" && local.grafana_auth_list.google.allowed_groups == "") ||
      (provider == "github" && local.grafana_auth_list.github.allowed_organizations == "" && local.grafana_auth_list.github.team_ids == "") ||
      (provider == "gitlab" && local.grafana_gitlab_url == "" && local.grafana_auth_list.gitlab.allowed_groups == "")
    )
  ]

  grafana_auth_without_client = [
    for provider in local.grafana_auth_providers : provider
    if try(trimspace(local.grafana_auth_config[provider].client_id), "") == "" || try(trimspace(local.grafana_auth_config[provider].client_secret_arn), "") == ""
  ]

  grafana_auth_without_endpoint = [
    for provider in local.grafana_auth_providers : provider if(
      (provider == "azuread" && local.grafana_tenant_id == "") ||
      (provider == "okta" && local.grafana_okta_url == "") ||
      (provider == "generic_oauth" && (local.grafana_auth_settings.generic_oauth.auth_url == "" || local.grafana_auth_settings.generic_oauth.token_url == ""))
    )
  ]

  grafana_auth_settings_with_secrets = [
    for provider in local.grafana_auth_providers : provider
    if length(setintersection(keys(local.grafana_auth_config[provider].settings), ["client_secret", "enabled"])) > 0
  ]
}
