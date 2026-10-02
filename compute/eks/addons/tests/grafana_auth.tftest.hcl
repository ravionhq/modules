################################################################################
# In-cluster Grafana sign-in: Grafana's own providers
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/mock/0123456789abcdef/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      id  = "ws-11111111-2222-3333-4444-555555555555"
      arn = "arn:aws:aps:us-east-2:123456789012:workspace/ws-11111111-2222-3333-4444-555555555555"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}

mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name                 = "test-cluster"
  region                       = "us-east-2"
  cluster_security_group_id    = "sg-12345678"
  public_subnet_ids            = ["subnet-0a", "subnet-0b"]
  node_subnet_ids              = ["subnet-1a", "subnet-1b"]
  public_alb_creation_enabled  = true
  public_alb_https_enabled     = true
  public_alb_certificate_arns  = ["arn:aws:acm:us-east-2:123456789012:certificate/11111111-2222-3333-4444-555555555555"]
  private_alb_creation_enabled = true
  private_alb_https_enabled    = true
  private_alb_certificate_arns = ["arn:aws:acm:us-east-2:123456789012:certificate/66666666-7777-8888-9999-000000000000"]
  karpenter_enabled            = false
  eso_enabled                  = true
  eso_allowed_namespaces       = ["apps"]
  logs_providers               = ["loki"]
  metrics_providers            = ["prometheus"]
  traces_providers             = ["tempo"]
  ravion_operator_enabled      = false
  grafana_enabled              = true
}

run "username_and_password_only_by_default" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].auth == { sigv4_auth_enabled = true } && !contains(keys(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]), "auth.basic") && length([for section in keys(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]) : section if startswith(section, "auth.") && section != "auth.basic"]) == 0
    error_message = "By default Grafana must keep username and password sign-in and turn on no provider"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].users.auto_assign_org_role == "Viewer" && try(yamldecode(helm_release.grafana[0].values[0]).envValueFrom, {}) == {}
    error_message = "New accounts must default to Viewer, with no provider secret mounted"
  }
}

run "google_restricted_to_workspace_domains" {
  command = plan

  variables {
    grafana_auth_providers = ["google"]
    grafana_auth_google = {
      client_id         = "1234.apps.googleusercontent.com"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      allowed_domains   = ["example.com", " example.org "]
    }
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].enabled == true && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].client_id == "1234.apps.googleusercontent.com" && jsondecode(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.google"].allowed_domains) == ["example.com", "example.org"]
    error_message = "Google sign-in must be on for the allowed domains, under Grafana's own keys"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0]).envValueFrom.GF_AUTH_GOOGLE_CLIENT_SECRET.secretKeyRef.name == "ravion-grafana-google-oauth" && !strcontains(helm_release.grafana[0].values[0], "client_secret")
    error_message = "The client secret must come from a Kubernetes Secret, never a Helm value"
  }

  assert {
    condition     = contains([for secret in yamldecode(helm_release.observability_secrets[0].values[0]).externalSecrets : secret.name], "ravion-grafana-google-oauth")
    error_message = "External Secrets must materialize the client secret"
  }

  assert {
    condition     = contains(yamldecode(helm_release.external_secrets_stores[0].values[0]).allowedNamespaces, "ravion-operator")
    error_message = "The secret store must admit Grafana's namespace beside the workload allow-list"
  }
}

run "several_providers_side_by_side" {
  command = plan

  variables {
    grafana_auth_providers = ["github", "azuread", "okta", "gitlab", "generic_oauth"]
    grafana_auth_github = {
      client_id             = "gh-client"
      client_secret_arn     = "arn:aws:secretsmanager:us-east-2:123456789012:secret:gh-AbCdEf"
      allowed_organizations = ["Example Org"]
      team_ids              = ["150"]
    }
    grafana_auth_azuread = {
      client_id         = "entra-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:entra-AbCdEf"
      tenant_id         = "11111111-2222-3333-4444-555555555555"
    }
    grafana_auth_okta = {
      client_id         = "okta-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:okta-AbCdEf"
      url               = "https://example.okta.com/"
      allowed_groups    = ["grafana-users"]
    }
    grafana_auth_gitlab = {
      client_id         = "gl-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:gl-AbCdEf"
      url               = "https://gitlab.example.com"
    }
    grafana_auth_generic_oauth = {
      name                = "Keycloak"
      client_id           = "kc-client"
      client_secret_arn   = "arn:aws:secretsmanager:us-east-2:123456789012:secret:kc-AbCdEf"
      auth_url            = "https://sso.example.com/realms/eng/protocol/openid-connect/auth"
      token_url           = "https://sso.example.com/realms/eng/protocol/openid-connect/token"
      api_url             = "https://sso.example.com/realms/eng/protocol/openid-connect/userinfo"
      scopes              = "openid email profile"
      role_attribute_path = "contains(roles[*], 'admin') && 'Admin' || 'Viewer'"
      settings            = { use_pkce = "true", login_attribute_path = "preferred_username" }
    }
  }

  assert {
    condition     = jsondecode(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.github"].allowed_organizations) == ["Example Org"] && jsondecode(yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.github"].team_ids) == ["150"]
    error_message = "GitHub must keep an organization name with a space in it whole"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.azuread"].auth_url == "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/authorize" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.azuread"].token_url == "https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/oauth2/v2.0/token"
    error_message = "Entra ID must sign in against the tenant's endpoints"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.okta"].auth_url == "https://example.okta.com/oauth2/v1/authorize" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.okta"].api_url == "https://example.okta.com/oauth2/v1/userinfo"
    error_message = "Okta must sign in against the org's endpoints"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.gitlab"].api_url == "https://gitlab.example.com/api/v4"
    error_message = "A self-managed GitLab must be signed in against its own URL"
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.generic_oauth"].name == "Keycloak" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.generic_oauth"].use_pkce == "true" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.generic_oauth"].login_attribute_path == "preferred_username" && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.generic_oauth"].role_attribute_path == "contains(roles[*], 'admin') && 'Admin' || 'Viewer'"
    error_message = "A generic provider must carry its typed settings and pass any other Grafana key through verbatim"
  }

  assert {
    condition     = toset(keys(yamldecode(helm_release.grafana[0].values[0]).envValueFrom)) == toset(["GF_AUTH_GITHUB_CLIENT_SECRET", "GF_AUTH_AZUREAD_CLIENT_SECRET", "GF_AUTH_OKTA_CLIENT_SECRET", "GF_AUTH_GITLAB_CLIENT_SECRET", "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET"]) && yamldecode(helm_release.grafana[0].values[0]).envValueFrom.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET.secretKeyRef.name == "ravion-grafana-generic-oauth-oauth"
    error_message = "Each provider's client secret must reach Grafana from its own Secret"
  }
}

run "providers_only_turns_off_passwords_everywhere" {
  command = plan

  variables {
    grafana_auth = {
      login_form_enabled = false
      default_role       = "Editor"
    }
    grafana_auth_providers = ["google"]
    grafana_auth_google = {
      client_id         = "1234.apps.googleusercontent.com"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      allowed_domains   = ["example.com"]
    }
  }

  assert {
    condition     = yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].auth.disable_login_form == true && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"]["auth.basic"].enabled == false && yamldecode(helm_release.grafana[0].values[0])["grafana.ini"].users.auto_assign_org_role == "Editor"
    error_message = "Without username and password, both the login form and HTTP basic auth must be off"
  }
}

run "rejects_no_way_to_sign_in" {
  command = plan

  variables {
    grafana_auth = {
      login_form_enabled = false
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_a_provider_without_its_client" {
  command = plan

  variables {
    grafana_auth_providers = ["okta"]
    grafana_auth_okta = {
      url = "https://example.okta.com"
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_google_open_to_every_account" {
  command = plan

  variables {
    grafana_auth_providers = ["google"]
    grafana_auth_google = {
      client_id         = "1234.apps.googleusercontent.com"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_github_open_to_every_account" {
  command = plan

  variables {
    grafana_auth_providers = ["github"]
    grafana_auth_github = {
      client_id         = "gh-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:gh-AbCdEf"
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_entra_without_a_tenant" {
  command = plan

  variables {
    grafana_auth_providers = ["azuread"]
    grafana_auth_azuread = {
      client_id         = "entra-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:entra-AbCdEf"
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_a_client_secret_in_settings" {
  command = plan

  variables {
    grafana_auth_providers = ["generic_oauth"]
    grafana_auth_generic_oauth = {
      client_id         = "kc-client"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:kc-AbCdEf"
      auth_url          = "https://sso.example.com/auth"
      token_url         = "https://sso.example.com/token"
      settings          = { client_secret = "do-not-do-this" }
    }
  }

  expect_failures = [helm_release.grafana]
}

run "rejects_unknown_provider" {
  command = plan

  variables {
    grafana_auth_providers = ["facebook"]
  }

  expect_failures = [var.grafana_auth_providers]
}

run "rejects_unknown_role" {
  command = plan

  variables {
    grafana_auth = {
      default_role = "Owner"
    }
  }

  expect_failures = [var.grafana_auth]
}

run "rejects_provider_secrets_without_external_secrets" {
  command = plan

  variables {
    eso_enabled            = false
    grafana_auth_providers = ["google"]
    grafana_auth_google = {
      client_id         = "1234.apps.googleusercontent.com"
      client_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-google-AbCdEf"
      allowed_domains   = ["example.com"]
    }
  }

  expect_failures = [helm_release.observability_secrets]
}
