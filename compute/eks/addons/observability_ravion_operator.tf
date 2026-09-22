################################################################################
# What Ravion Operator may proxy a query to
#
# Ravion never dials into a cluster: the dashboard's Logs and Metrics tabs read
# a store by asking the agent to make the request from inside. Which URLs the
# agent will make a request to is an allowlist in its own Helm values, so it is
# something the customer reads in their own Terraform rather than something the
# control plane names at query time.
#
# Three kinds of destination end up on that list:
#
#   1. THE IN-CLUSTER STORES. Loki, and (from 0.8.1) the in-cluster Prometheus.
#      ClusterIP Services with no route out of the cluster at all, which is why
#      the agent is the only thing that can reach them.
#
#   2. EXTERNAL STORES RAVION RENDERS FROM. Grafana Cloud's query endpoints.
#      These are reachable from the internet, but the credential is not: it
#      lives in a Kubernetes Secret the agent reads, so a proxied query carries
#      an Authorization header the control plane never sees.
#
#   3. NOTHING ELSE. A ship-only vendor gets a link in the tab, not a proxy
#      entry — Ravion does not query Datadog on the customer's behalf.
#
# The credential entries name a Secret, never a value. Ravion Operator attaches the
# Authorization header for requests under the matching prefix and forwards no
# caller-supplied one, which is the rule that keeps this from being an open
# proxy with the cluster's credentials attached.
################################################################################

locals {
  ravion_operator_grafana_cloud_logs_secret_name    = "ravion-observability-grafana-cloud-logs"
  ravion_operator_grafana_cloud_metrics_secret_name = "ravion-observability-grafana-cloud-metrics"

  # Materialized into Ravion Operator's namespace, not the collectors': the agent mounts
  # them, and a Secret is not readable across namespaces.
  ravion_operator_proxy_credential_secrets = concat(
    var.ravion_operator_enabled && local.logs_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.logs_user != null ? [{
      name      = local.ravion_operator_grafana_cloud_logs_secret_name
      namespace = var.ravion_operator_namespace
      template = {
        username = local.grafana_cloud_config.logs_user
        password = "{{ .token }}"
      }
      data = [{
        secretKey = "token"
        remoteRef = local.grafana_cloud_config.token_secret_arn
      }]
    }] : [],
    var.ravion_operator_enabled && local.metrics_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.metrics_user != null ? [{
      name      = local.ravion_operator_grafana_cloud_metrics_secret_name
      namespace = var.ravion_operator_namespace
      template = {
        username = local.grafana_cloud_config.metrics_user
        password = "{{ .token }}"
      }
      data = [{
        secretKey = "token"
        remoteRef = local.grafana_cloud_config.token_secret_arn
      }]
    }] : [],
  )

  # Prefixes, in the order the dashboard's fallback chain reads them.
  ravion_operator_proxy_allowed_endpoints = compact(concat(
    [local.loki_enabled ? local.loki_endpoint : ""],
    [local.grafana_cloud_logs_query_url != null ? local.grafana_cloud_logs_query_url : ""],
    [local.grafana_cloud_metrics_query_url != null ? local.grafana_cloud_metrics_query_url : ""],
    [local.prometheus_endpoint != null ? local.prometheus_endpoint : ""],
  ))

  ravion_operator_proxy_credentials = concat(
    local.grafana_cloud_logs_query_url != null && length([for secret in local.ravion_operator_proxy_credential_secrets : secret if secret.name == local.ravion_operator_grafana_cloud_logs_secret_name]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_logs_query_url
      secretName     = local.ravion_operator_grafana_cloud_logs_secret_name
      kind           = "basic"
    }] : [],
    local.grafana_cloud_metrics_query_url != null && length([for secret in local.ravion_operator_proxy_credential_secrets : secret if secret.name == local.ravion_operator_grafana_cloud_metrics_secret_name]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_metrics_query_url
      secretName     = local.ravion_operator_grafana_cloud_metrics_secret_name
      kind           = "basic"
    }] : [],
  )

  # The single name the control plane carries as `auth_secret` on a source it
  # proxies. Logs first: the Logs tab is the one that reaches an external store
  # in 0.8.x. ravion_operator_proxy_credentials is the full mapping.
  observability_credentials_secret_name = length(local.ravion_operator_proxy_credentials) > 0 ? local.ravion_operator_proxy_credentials[0].secretName : null

  ravion_operator_observability_proxy_values = var.ravion_operator_enabled && length(local.ravion_operator_proxy_allowed_endpoints) > 0 ? [
    yamlencode({
      httpProxy = {
        enabled          = true
        allowedEndpoints = local.ravion_operator_proxy_allowed_endpoints
        credentials      = local.ravion_operator_proxy_credentials
      }
    }),
  ] : []
}
