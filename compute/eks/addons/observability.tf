################################################################################
# Observability providers — selection, fallbacks, and everything derived
#
# ONE MULTI-SELECT PER SIGNAL. logs_providers and metrics_providers name every
# destination the cluster ships to. Loki and AMP are the defaults, so a fresh
# instance renders both tabs with no configuration; CloudWatch is a member of
# the same lists and is never installed as a side effect of anything.
#
# Three things this file establishes:
#
#   1. THE LISTS ARE THE ONLY SWITCH. logs_providers and metrics_providers say
#      everything: an empty list is the signal turned off, and the module
#      definition passes one when the section's toggle is off. The booleans this
#      module carried before 0.8.0 are gone as of 0.8.2.
#
#   2. RENDERING ORDER IS A CONTRACT. logs_rendering_providers and
#      metrics_rendering_providers are the selected members of a fixed list, in
#      a fixed order: logs loki -> cloudwatch, metrics amp -> prometheus ->
#      cloudwatch. The dashboard walks that order and reads the first store that
#      can answer, so the order here is the order a service module lists its
#      ui.logs / ui.metrics entries in.
#
#   3. VENDOR SETTINGS ARE SHARED ACROSS SIGNALS. A team that picks Datadog for
#      both logs and metrics fills the site and the key ARN once; the form
#      declares one field and maps it into both provider objects, and the merge
#      below is what makes either one authoritative.
################################################################################

locals {
  ##############################################################################
  # Effective provider lists
  ##############################################################################

  logs_providers    = distinct(var.logs_providers)
  metrics_providers = distinct(var.metrics_providers)

  # Selected members of the rendering lists, in fallback order. Empty when the
  # signal is off, which is what the tabs read as "turned off for this cluster".
  logs_rendering_providers    = tolist([for provider in ["loki", "cloudwatch"] : provider if contains(local.logs_providers, provider)])
  metrics_rendering_providers = tolist([for provider in ["amp", "prometheus", "cloudwatch"] : provider if contains(local.metrics_providers, provider)])

  logs_on    = length(local.logs_providers) > 0
  metrics_on = length(local.metrics_providers) > 0

  # Per-provider guards. Every resource in the module hangs off one of these
  # rather than off a variable, so "is this installed" has exactly one answer.
  loki_enabled                  = contains(local.logs_providers, "loki")
  amp_enabled                   = contains(local.metrics_providers, "amp")
  prometheus_enabled            = contains(local.metrics_providers, "prometheus")
  logs_cloudwatch_enabled       = contains(local.logs_providers, "cloudwatch")
  metrics_cloudwatch_enabled    = contains(local.metrics_providers, "cloudwatch")
  cloudwatch_addon_enabled      = local.logs_cloudwatch_enabled || local.metrics_cloudwatch_enabled
  logs_grafana_cloud_enabled    = contains(local.logs_providers, "grafana_cloud")
  logs_datadog_enabled          = contains(local.logs_providers, "datadog")
  logs_new_relic_enabled        = contains(local.logs_providers, "new_relic")
  logs_opensearch_enabled       = contains(local.logs_providers, "opensearch")
  logs_splunk_enabled           = contains(local.logs_providers, "splunk")
  logs_otlp_enabled             = contains(local.logs_providers, "otlp")
  metrics_grafana_cloud_enabled = contains(local.metrics_providers, "grafana_cloud")
  metrics_datadog_enabled       = contains(local.metrics_providers, "datadog")
  metrics_new_relic_enabled     = contains(local.metrics_providers, "new_relic")
  metrics_otlp_enabled          = contains(local.metrics_providers, "otlp")
  grafana_cloud_enabled         = local.logs_grafana_cloud_enabled || local.metrics_grafana_cloud_enabled

  # Alloy carries the loki-family destinations; the OpenTelemetry collector
  # carries every other log destination. Either can be the only one running.
  alloy_log_providers = [for provider in ["loki", "grafana_cloud"] : provider if contains(local.logs_providers, provider)]
  otel_logs_providers = [
    for provider in ["cloudwatch", "datadog", "new_relic", "opensearch", "splunk", "otlp"] :
    provider if contains(local.logs_providers, provider)
  ]

  alloy_enabled             = length(local.alloy_log_providers) > 0
  otel_logs_enabled         = length(local.otel_logs_providers) > 0
  otel_metrics_providers    = [for provider in local.metrics_providers : provider if provider != "cloudwatch"]
  otel_metrics_enabled      = length(local.otel_metrics_providers) > 0
  kube_state_metrics_wanted = local.otel_metrics_enabled

  ##############################################################################
  # Per-provider settings, with the older flat variables as fallbacks
  ##############################################################################

  loki_config = {
    retention_days      = var.logs_loki.retention_days != null ? var.logs_loki.retention_days : var.log_retention_days
    s3_bucket           = var.logs_loki.s3_bucket_name != null ? var.logs_loki.s3_bucket_name : var.loki_s3_bucket_name
    persistence_enabled = var.logs_loki.persistence_enabled != null ? var.logs_loki.persistence_enabled : var.loki_persistence_enabled
    persistence_size    = var.logs_loki.persistence_size != null ? var.logs_loki.persistence_size : var.loki_persistence_size
  }

  cloudwatch_logs_config = {
    retention_days = var.logs_cloudwatch.retention_days != null ? var.logs_cloudwatch.retention_days : 30
    log_group_name = var.logs_cloudwatch.log_group_name != null ? var.logs_cloudwatch.log_group_name : "/ravion/eks/${var.cluster_name}"
  }

  cloudwatch_metrics_config = {
    enhanced_observability         = var.metrics_cloudwatch.enhanced_observability_enabled != null ? var.metrics_cloudwatch.enhanced_observability_enabled : true
    application_signals_enabled    = coalesce(var.metrics_cloudwatch.application_signals_enabled, false)
    application_signals_namespaces = coalesce(var.metrics_cloudwatch.application_signals_namespaces, [])
    addon_version                  = var.metrics_cloudwatch.addon_version != null ? var.metrics_cloudwatch.addon_version : var.cloudwatch_observability_addon_version
    addon_configuration_values     = var.metrics_cloudwatch.addon_configuration_values != null ? var.metrics_cloudwatch.addon_configuration_values : var.cloudwatch_observability_addon_configuration_values
  }

  amp_config = {
    workspace_id = var.metrics_amp.workspace_id != null ? var.metrics_amp.workspace_id : var.amp_workspace_id
    region       = var.metrics_amp.region != null ? var.metrics_amp.region : var.amp_region
    alias        = var.metrics_amp.alias != null ? var.metrics_amp.alias : var.amp_alias
  }

  # Shared across signals: the same vendor account, whichever signal named it.
  datadog_config = {
    site               = coalesce(var.logs_datadog.site, var.metrics_datadog.site, "datadoghq.com")
    api_key_secret_arn = try(coalesce(var.logs_datadog.api_key_secret_arn, var.metrics_datadog.api_key_secret_arn), null)
  }

  new_relic_config = {
    region                 = coalesce(var.logs_new_relic.region, var.metrics_new_relic.region, "us")
    license_key_secret_arn = try(coalesce(var.logs_new_relic.license_key_secret_arn, var.metrics_new_relic.license_key_secret_arn), null)
  }

  grafana_cloud_config = {
    logs_url         = var.logs_grafana_cloud.url
    logs_user        = var.logs_grafana_cloud.user
    metrics_url      = var.metrics_grafana_cloud.url
    metrics_user     = var.metrics_grafana_cloud.user
    token_secret_arn = try(coalesce(var.logs_grafana_cloud.token_secret_arn, var.metrics_grafana_cloud.token_secret_arn), null)
    stack_url        = try(coalesce(var.logs_grafana_cloud.stack_url, var.metrics_grafana_cloud.stack_url), null)
  }

  prometheus_config = {
    retention_days = coalesce(var.metrics_prometheus.retention_days, 15)
    storage_size   = coalesce(var.metrics_prometheus.storage_size, "50Gi")
    endpoint       = var.metrics_prometheus.endpoint
  }

  opensearch_config = {
    endpoint     = var.logs_opensearch.endpoint
    index_prefix = coalesce(var.logs_opensearch.index_prefix, "ravion-logs")
  }

  splunk_config = {
    hec_url              = var.logs_splunk.hec_url
    hec_token_secret_arn = var.logs_splunk.hec_token_secret_arn
    index                = var.logs_splunk.index
  }

  otlp_logs_config = {
    endpoint           = var.logs_otlp.endpoint
    headers_secret_arn = var.logs_otlp.headers_secret_arn
  }

  otlp_metrics_config = {
    endpoint           = var.metrics_otlp.endpoint
    headers_secret_arn = var.metrics_otlp.headers_secret_arn
  }

  # New Relic publishes one OTLP endpoint per data region.
  new_relic_otlp_endpoint = local.new_relic_config.region == "eu" ? "https://otlp.eu01.nr-data.net" : "https://otlp.nr-data.net"

  ##############################################################################
  # Derived endpoints
  ##############################################################################

  # The cluster's own region: where the CloudWatch log group lives, and what the
  # log collector signs for. AMP has its own region, which may differ.
  observability_region = coalesce(var.region, data.aws_region.current.region)

  cloudwatch_log_group_name = local.logs_cloudwatch_enabled ? local.cloudwatch_logs_config.log_group_name : null

  prometheus_release_name = "ravion-prometheus"

  # The chart names the server Service <fullname>-server; fullnameOverride pins
  # the first half so the URL is a constant rather than a function of the
  # release name. Port 9090 is set on the Service to match the container's.
  prometheus_service_host = "${local.prometheus_release_name}-server.${local.observability_namespace}.svc.cluster.local"

  # Installed here, or one the customer already runs.
  prometheus_install = local.prometheus_enabled && local.prometheus_config.endpoint == null

  prometheus_endpoint = local.prometheus_enabled ? (
    local.prometheus_config.endpoint != null ? local.prometheus_config.endpoint : "http://${local.prometheus_service_host}:9090"
  ) : null

  prometheus_remote_write_endpoint = local.prometheus_enabled ? "${local.prometheus_endpoint}/api/v1/write" : null

  # Grafana Cloud hands out a push URL; the query base is the same service with
  # the push path removed. Loki: <base>/loki/api/v1/push -> <base>/loki.
  # Prometheus: <base>/api/prom/push -> <base>/api/prom.
  grafana_cloud_logs_query_url = local.logs_grafana_cloud_enabled && local.grafana_cloud_config.logs_url != null ? (
    replace(local.grafana_cloud_config.logs_url, "/api/v1/push", "")
  ) : null

  grafana_cloud_metrics_query_url = local.metrics_grafana_cloud_enabled && local.grafana_cloud_config.metrics_url != null ? (
    replace(local.grafana_cloud_config.metrics_url, "/push", "")
  ) : null

  ##############################################################################
  # Vendor credentials
  #
  # One Kubernetes Secret per vendor, materialized by the External Secrets
  # Operator from a Secrets Manager ARN into the collector namespace. The
  # collectors read them as environment variables; no value is ever a Helm value
  # or a Terraform output.
  ##############################################################################

  vendor_secrets = concat(
    local.datadog_config.api_key_secret_arn != null && (local.logs_datadog_enabled || local.metrics_datadog_enabled) ? [{
      provider    = "datadog"
      name        = "ravion-observability-datadog"
      secret_key  = "apiKey"
      remote_ref  = local.datadog_config.api_key_secret_arn
      environment = "DATADOG_API_KEY"
    }] : [],
    local.new_relic_config.license_key_secret_arn != null && (local.logs_new_relic_enabled || local.metrics_new_relic_enabled) ? [{
      provider    = "new_relic"
      name        = "ravion-observability-new-relic"
      secret_key  = "licenseKey"
      remote_ref  = local.new_relic_config.license_key_secret_arn
      environment = "NEW_RELIC_LICENSE_KEY"
    }] : [],
    local.grafana_cloud_config.token_secret_arn != null && local.grafana_cloud_enabled ? [{
      provider    = "grafana_cloud"
      name        = "ravion-observability-grafana-cloud"
      secret_key  = "token"
      remote_ref  = local.grafana_cloud_config.token_secret_arn
      environment = "GRAFANA_CLOUD_TOKEN"
    }] : [],
    local.splunk_config.hec_token_secret_arn != null && local.logs_splunk_enabled ? [{
      provider    = "splunk"
      name        = "ravion-observability-splunk"
      secret_key  = "token"
      remote_ref  = local.splunk_config.hec_token_secret_arn
      environment = "SPLUNK_HEC_TOKEN"
    }] : [],
    local.otlp_logs_config.headers_secret_arn != null && local.logs_otlp_enabled ? [{
      provider    = "otlp_logs"
      name        = "ravion-observability-otlp-logs"
      secret_key  = "authorization"
      remote_ref  = local.otlp_logs_config.headers_secret_arn
      environment = "OTLP_LOGS_AUTHORIZATION"
    }] : [],
    local.otlp_metrics_config.headers_secret_arn != null && local.metrics_otlp_enabled ? [{
      provider    = "otlp_metrics"
      name        = "ravion-observability-otlp-metrics"
      secret_key  = "authorization"
      remote_ref  = local.otlp_metrics_config.headers_secret_arn
      environment = "OTLP_METRICS_AUTHORIZATION"
    }] : [],
  )

  # Which vendor Secrets each collector mounts as environment variables.
  alloy_secret_env = [
    for secret in local.vendor_secrets : secret
    if secret.provider == "grafana_cloud" && local.logs_grafana_cloud_enabled
  ]

  otel_logs_secret_env = [
    for secret in local.vendor_secrets : secret
    if contains(["datadog", "new_relic", "splunk", "otlp_logs"], secret.provider)
  ]

  otel_metrics_secret_env = [
    for secret in local.vendor_secrets : secret
    if contains(["datadog", "new_relic", "grafana_cloud", "otlp_metrics"], secret.provider)
  ]

  ##############################################################################
  # "Open in <vendor>" links
  #
  # href_prefix is a base URL the service module completes with its own
  # namespace/workload query. The module publishes the prefix and nothing more:
  # the query syntax belongs to whoever renders the link.
  ##############################################################################

  logs_external_links = concat(
    local.logs_datadog_enabled ? [{
      provider    = "datadog"
      name        = "Open in Datadog"
      href_prefix = "https://app.${local.datadog_config.site}/logs?query="
    }] : [],
    local.logs_new_relic_enabled ? [{
      provider    = "new_relic"
      name        = "Open in New Relic"
      href_prefix = local.new_relic_config.region == "eu" ? "https://one.eu.newrelic.com/logger?query=" : "https://one.newrelic.com/logger?query="
    }] : [],
    local.logs_grafana_cloud_enabled && local.grafana_cloud_config.stack_url != null ? [{
      provider    = "grafana_cloud"
      name        = "Open in Grafana Cloud"
      href_prefix = "${trimsuffix(local.grafana_cloud_config.stack_url, "/")}/explore?left="
    }] : [],
    local.logs_opensearch_enabled && local.opensearch_config.endpoint != null ? [{
      provider    = "opensearch"
      name        = "Open Dashboards"
      href_prefix = "${trimsuffix(local.opensearch_config.endpoint, "/")}/_dashboards/app/discover#/?_q="
    }] : [],
  )

  metrics_external_links = concat(
    local.metrics_datadog_enabled ? [{
      provider = "datadog"
      name     = "Open in Datadog"
      # exp_scope, not exp_metric: what the service module appends is the
      # namespace/pod tag query, which is the explorer's scope filter.
      href_prefix = "https://app.${local.datadog_config.site}/metric/explorer?exp_scope="
    }] : [],
    local.metrics_new_relic_enabled ? [{
      provider    = "new_relic"
      name        = "Open in New Relic"
      href_prefix = local.new_relic_config.region == "eu" ? "https://one.eu.newrelic.com/data-exploration?query=" : "https://one.newrelic.com/data-exploration?query="
    }] : [],
    local.metrics_grafana_cloud_enabled && local.grafana_cloud_config.stack_url != null ? [{
      provider    = "grafana_cloud"
      name        = "Open in Grafana Cloud"
      href_prefix = "${trimsuffix(local.grafana_cloud_config.stack_url, "/")}/explore?left="
    }] : [],
  )

  ##############################################################################
  # Log collector image
  #
  # The AWS Distro is the default because it is the distribution that carries
  # the sigv4auth extension the AMP remote write depends on — but it does not
  # ship the datadog, splunk_hec, opensearch or awscloudwatchlogs exporters. Any
  # selection that needs one of those runs the upstream contrib image instead,
  # which carries sigv4auth as well. Both are overridable.
  ##############################################################################

  metrics_needs_contrib = length([
    for provider in local.otel_metrics_providers : provider
    if contains(["datadog", "grafana_cloud", "new_relic", "otlp"], provider)
  ]) > 0

  otel_metrics_image_repository = var.otel_collector_image_repository != null ? var.otel_collector_image_repository : (
    local.metrics_needs_contrib ? var.otel_contrib_image_repository : "public.ecr.aws/aws-observability/aws-otel-collector"
  )

  otel_metrics_image_tag = var.otel_collector_image_tag != null ? var.otel_collector_image_tag : (
    local.metrics_needs_contrib ? var.otel_contrib_image_tag : "v0.49.0"
  )

  otel_metrics_command_name = var.otel_collector_command_name != null ? var.otel_collector_command_name : (
    local.metrics_needs_contrib ? var.otel_contrib_command_name : "awscollector"
  )
}
