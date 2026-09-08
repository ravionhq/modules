# Preserve materialized vendor query credentials and their stable Secret names.
# These describe external query authentication; collectors continue using ESO.
locals {
  observability_proxy_credential_secrets = concat(
    local.logs_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.logs_user != null ? [{
      name      = "ravion-observability-grafana-cloud-logs"
      namespace = local.observability_namespace
      template  = { username = local.grafana_cloud_config.logs_user, password = "{{ .token }}" }
      data      = [{ secretKey = "token", remoteRef = local.grafana_cloud_config.token_secret_arn }]
    }] : [],
    local.metrics_grafana_cloud_enabled && local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_config.metrics_user != null ? [{
      name      = "ravion-observability-grafana-cloud-metrics"
      namespace = local.observability_namespace
      template  = { username = local.grafana_cloud_config.metrics_user, password = "{{ .token }}" }
      data      = [{ secretKey = "token", remoteRef = local.grafana_cloud_config.token_secret_arn }]
    }] : [],
  )
  observability_proxy_credentials = concat(
    local.grafana_cloud_logs_query_url != null && length([for secret in local.observability_proxy_credential_secrets : secret if secret.name == "ravion-observability-grafana-cloud-logs"]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_logs_query_url
      secretName     = "ravion-observability-grafana-cloud-logs"
      kind           = "basic"
    }] : [],
    local.grafana_cloud_metrics_query_url != null && length([for secret in local.observability_proxy_credential_secrets : secret if secret.name == "ravion-observability-grafana-cloud-metrics"]) > 0 ? [{
      endpointPrefix = local.grafana_cloud_metrics_query_url
      secretName     = "ravion-observability-grafana-cloud-metrics"
      kind           = "basic"
    }] : [],
  )
  observability_credentials_secret_name = length(local.observability_proxy_credentials) > 0 ? local.observability_proxy_credentials[0].secretName : null
}
