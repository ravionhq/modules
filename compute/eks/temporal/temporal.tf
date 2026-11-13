################################################################################
# Temporal
#
# Two releases in the same namespace:
#
#   1. temporal-resources (a local chart): the database password Secret (through
#      the External Secrets Operator), the RDS CA bundle, the private CA and
#      certificates, the PriorityClass, the dedicated NodePool, the network
#      policies and the metrics forwarder. Installed first, because the
#      Temporal pods mount the Secret, the CA bundle and the certificates.
#
#   2. The upstream temporalio/helm-charts `temporal` chart: frontend, history,
#      matching and worker services, the Web UI, the admin tools, the schema
#      job that creates and migrates both databases, and the job that creates
#      the Temporal namespaces.
#
# Both releases set upgrade_install so an apply adopts a same-named release
# already in the cluster instead of failing with "cannot re-use a name that is
# still in use".
################################################################################

resource "helm_release" "temporal_resources" {
  name      = local.resources_release_name
  namespace = var.namespace
  chart     = "${path.module}/charts/temporal-resources"
  # Pinned so a Chart.yaml bump shows in the plan.
  version          = yamldecode(file("${path.module}/charts/temporal-resources/Chart.yaml")).version
  create_namespace = var.namespace_creation_enabled
  upgrade_install  = true

  values = [yamlencode(local.resources_values)]

  lifecycle {
    precondition {
      condition     = startswith(local.database_engine, "aurora-postgresql")
      error_message = "The database cluster runs ${local.database_engine}. This module supports Aurora PostgreSQL only."
    }
    precondition {
      condition     = !local.database_external_secret || var.database_password_secret_arn != null
      error_message = "database_password_secret_arn is required when database_password_source is external_secrets. Use the Aurora module's cluster_master_user_secret_arn output, or set database_password_source = \"kubernetes_secret\"."
    }
    precondition {
      condition     = !var.tls_enabled || var.tls_ca_source != "issuer" || var.tls_issuer != null
      error_message = "tls_issuer is required when tls_ca_source is issuer."
    }
    precondition {
      condition     = !var.tls_enabled || var.tls_ca_source != "secret" || var.tls_ca_secret_name != null
      error_message = "tls_ca_secret_name is required when tls_ca_source is secret."
    }
    precondition {
      condition     = !var.jwt_auth_enabled || var.tls_enabled
      error_message = "jwt_auth_enabled requires tls_enabled: Temporal's own components reach the internal frontend with internode certificates instead of tokens."
    }
    precondition {
      condition     = !var.jwt_auth_enabled || (var.jwt_auth_jwks_source == "url" ? length(var.jwt_auth_jwks_urls) > 0 : var.jwt_auth_jwks_secret_arn != null)
      error_message = "jwt_auth_enabled needs signing keys: jwt_auth_jwks_urls for jwt_auth_jwks_source = url, or jwt_auth_jwks_secret_arn for secrets_manager."
    }
    precondition {
      condition     = !var.frontend_nlb_enabled || length(var.frontend_nlb_source_cidrs) > 0
      error_message = "frontend_nlb_enabled needs frontend_nlb_source_cidrs: the client networks allowed to reach the NLB."
    }
    precondition {
      condition     = !local.oidc_enabled || var.web_oidc_client_secret_arn != null
      error_message = "web_oidc_enabled needs web_oidc_client_secret_arn: the Secrets Manager secret holding the OIDC client ID and secret."
    }
    precondition {
      condition     = !local.oidc_enabled || (local.oidc_issuer_url != "" && length(local.oidc_scopes) > 0)
      error_message = "web_oidc_enabled needs an issuer URL and scopes: set web_oidc_issuer_url for okta and microsoft_entra, and both web_oidc_issuer_url and web_oidc_scopes for generic."
    }
    precondition {
      condition     = !local.oidc_enabled || local.oidc_callback_url != null
      error_message = "web_oidc_enabled needs a callback URL: enable the Tailscale Web UI with tailscale_tailnet_domain, or the ingress with web_ingress_host, or set web_oidc_callback_url."
    }
  }
}

resource "helm_release" "temporal" {
  name             = var.name
  namespace        = var.namespace
  repository       = "https://go.temporal.io/helm-charts"
  chart            = "temporal"
  version          = var.chart_version
  create_namespace = false
  upgrade_install  = true

  # The schema job must finish before the servers can start, and the first
  # install waits for both.
  wait          = true
  wait_for_jobs = true
  timeout       = var.helm_timeout_seconds

  values = concat(
    [yamlencode(local.temporal_values)],
    var.helm_values,
  )

  depends_on = [helm_release.temporal_resources]
}
