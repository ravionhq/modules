################################################################################
# Observability providers
#
# The provider multi-selects: what a default instance installs, how the
# deprecated booleans map onto the lists, and what each provider adds. Run from
# the module root: `tofu test`.
#
# Karpenter is off in every run: it pulls in submodules and Helm releases that
# have nothing to do with what is asserted here.
################################################################################

mock_provider "aws" {
  # The mock provider's generated string is not valid JSON, which fails
  # provider-side validation on every resource that consumes a policy document.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id     = "us-east-2"
      name   = "us-east-2"
      region = "us-east-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  # The helm provider is configured from this data source, and its CA is
  # base64-decoded while the provider is configured — a random mock value would
  # fail the decode before any run block executes.
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.gr7.us-east-2.eks.amazonaws.com"
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
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      id  = "ws-11111111-2222-3333-4444-555555555555"
      arn = "arn:aws:aps:us-east-2:123456789012:workspace/ws-11111111-2222-3333-4444-555555555555"
    }
  }
}

mock_provider "helm" {}

# Ravion Operator's credential resource is minted by Ravion's own provider, which refuses
# to configure without a runner JWT. Nothing here exercises it.
mock_provider "ravion" {}

# Both signals start empty so every run opts into exactly the providers it is
# about. The defaults ([loki] and [amp]) have their own coverage in
# observability.tftest.hcl.

variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
}

################################################################################
# The default instance. Loki and AMP, nothing else — and in particular nothing
# CloudWatch, which is the whole point of the restructure.
################################################################################

run "defaults_are_loki_and_amp_and_nothing_cloudwatch" {
  command = plan

  assert {
    condition     = join(",", output.logs_providers) == "loki" && join(",", output.metrics_providers) == "amp"
    error_message = "A fresh instance must select the in-cluster log store and Amazon Managed Prometheus"
  }

  assert {
    condition     = join(",", output.logs_rendering_providers) == "loki" && join(",", output.metrics_rendering_providers) == "amp"
    error_message = "Both defaults render in Ravion, so both must appear in the rendering chains"
  }

  assert {
    condition     = length(aws_eks_addon.cloudwatch_observability) == 0 && length(module.cloudwatch_observability_role) == 0
    error_message = "Nothing CloudWatch may be installed as a side effect of the defaults"
  }

  assert {
    condition     = length(helm_release.loki) == 1 && length(helm_release.alloy) == 1 && length(helm_release.otel_collector) == 1
    error_message = "The default selection installs Loki, Alloy, and the metrics collector"
  }

  assert {
    condition     = length(helm_release.otel_logs_collector) == 0
    error_message = "With only the in-cluster store selected there is no second log collector to run"
  }

  assert {
    condition     = length(helm_release.observability_secrets) == 0
    error_message = "No vendor is selected, so there is no credential to materialize"
  }

  assert {
    condition     = length(output.logs_external_links) == 0 && length(output.metrics_external_links) == 0
    error_message = "No ship-only provider is selected, so there is nothing to link to"
  }
}

run "both_signals_can_be_turned_off" {
  command = plan

  variables {
    logs_providers    = []
    metrics_providers = []
  }

  assert {
    condition     = join(",", output.logs_rendering_providers) == "" && join(",", output.metrics_rendering_providers) == ""
    error_message = "Empty provider lists must render empty chains, which is what the tabs read as 'turned off'"
  }

  assert {
    condition     = length(helm_release.loki) == 0 && length(helm_release.alloy) == 0 && length(helm_release.otel_collector) == 0 && length(helm_release.kube_state_metrics) == 0
    error_message = "An empty selection installs no collector and no store"
  }
}

################################################################################
# CloudWatch as a provider. Auto-Monitor off is the assertion this file exists
# for: its default injects an agent into every workload in the cluster.
################################################################################

run "cloudwatch_metrics_provider_pins_auto_monitor_off" {
  command = plan

  variables {
    logs_providers    = ["loki"]
    metrics_providers = ["amp", "cloudwatch"]
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).manager.applicationSignals.autoMonitor.monitorAllServices == false
    error_message = "Auto-Monitor must be off: its default injects the AWS agent into every workload and restarts the pods"
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).containerLogs.enabled == false
    error_message = "cloudwatch is a metrics provider here, so the add-on's Fluent Bit half must stay off"
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).agent.enabled == true
    error_message = "cloudwatch in metrics_providers must install the metrics agent"
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).agent.config.logs.metrics_collected.kubernetes.enhanced_container_insights == true
    error_message = "Enhanced observability is on by default for the CloudWatch metrics provider"
  }

  assert {
    condition     = output.logs_cloudwatch_log_group == null
    error_message = "No log group is written to while cloudwatch is only a metrics provider"
  }
}

run "application_signals_is_opt_in_and_namespace_scoped" {
  command = plan

  variables {
    metrics_providers = ["cloudwatch"]
    metrics_cloudwatch = {
      application_signals_enabled    = true
      application_signals_namespaces = ["payments", "checkout"]
    }
  }

  # With a namespace list the cluster-wide switch stays off: the named
  # namespaces are annotated instead, which is what the output is for.
  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).manager.applicationSignals.autoMonitor.monitorAllServices == false
    error_message = "A namespace list must not turn on cluster-wide auto-instrumentation"
  }

  assert {
    condition     = join(",", output.cloudwatch_application_signals_namespaces) == "payments,checkout"
    error_message = "The namespaces to instrument must be published for the operator to annotate"
  }
}

run "application_signals_cluster_wide_is_explicit" {
  command = plan

  variables {
    metrics_providers = ["cloudwatch"]
    metrics_cloudwatch = {
      application_signals_enabled = true
    }
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).manager.applicationSignals.autoMonitor.monitorAllServices == true
    error_message = "Application Signals with no namespace list is a deliberate whole-cluster opt-in"
  }
}

run "cloudwatch_logs_provider_runs_the_otel_collector" {
  command = plan

  variables {
    logs_providers    = ["loki", "cloudwatch"]
    metrics_providers = []
  }

  assert {
    condition     = join(",", output.logs_rendering_providers) == "loki,cloudwatch"
    error_message = "Both rendering providers must appear, in fallback order"
  }

  assert {
    condition     = output.logs_cloudwatch_log_group == "/ravion/eks/test-cluster"
    error_message = "Ravion's CloudWatch log group is /ravion/eks/<cluster>"
  }

  assert {
    condition     = length(helm_release.otel_logs_collector) == 1 && length(helm_release.alloy) == 1
    error_message = "Loki plus CloudWatch means both collectors: Alloy for the store, OpenTelemetry for CloudWatch"
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.awscloudwatchlogs.log_group_name == "/ravion/eks/test-cluster"
    error_message = "The CloudWatch exporter must write to the Ravion log group"
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.service.pipelines.logs.exporters == ["awscloudwatchlogs"]
    error_message = "Only the selected providers may be on the log pipeline"
  }

  # The add-on's own Fluent Bit half is what containerLogs turns on.
  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).containerLogs.enabled == true
    error_message = "cloudwatch in logs_providers must turn the add-on's container logs half on"
  }

  assert {
    condition     = jsondecode(aws_eks_addon.cloudwatch_observability[0].configuration_values).agent.enabled == false
    error_message = "cloudwatch is not a metrics provider here, so the metrics agent must stay off"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.otel_logs_collector) == 1
    error_message = "The log collector needs its own Pod Identity association to write to CloudWatch"
  }
}

run "namespace_exclusions_reach_both_collectors" {
  command = plan

  variables {
    logs_providers           = ["loki", "cloudwatch"]
    metrics_providers        = []
    logs_excluded_namespaces = ["kube-system", "ravion-beacon"]
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "regex         = \"kube-system|ravion-beacon\"")
    error_message = "Alloy must drop excluded namespaces at discovery"
  }

  assert {
    condition     = contains(yamldecode(helm_release.otel_logs_collector[0].values[0]).config.receivers.filelog.exclude, "/var/log/pods/kube-system_*/*/*.log")
    error_message = "The OpenTelemetry collector must never open an excluded namespace's files"
  }
}

################################################################################
# Ship-only vendors: fan-out, credentials by reference, and the deep links.
################################################################################

run "datadog_ships_both_signals_from_one_credential" {
  command = plan

  variables {
    logs_providers    = ["loki", "datadog"]
    metrics_providers = ["amp", "datadog"]
    logs_datadog = {
      site               = "datadoghq.eu"
      api_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:datadog-api-key"
    }
  }

  # Declared once on the logs side and read by both, which is what "vendor
  # settings are shared across signals" means.
  assert {
    condition     = length(local.vendor_secrets) == 1 && local.vendor_secrets[0].name == "ravion-observability-datadog"
    error_message = "One Datadog credential must serve both signals"
  }

  assert {
    condition     = length(helm_release.observability_secrets) == 1
    error_message = "The credential must be materialized by External Secrets"
  }

  assert {
    condition     = yamldecode(helm_release.observability_secrets[0].values[0]).externalSecrets[0].data[0].remoteRef == "arn:aws:secretsmanager:us-east-2:123456789012:secret:datadog-api-key"
    error_message = "The ExternalSecret must reference the Secrets Manager ARN, never a value"
  }

  assert {
    condition     = !strcontains(helm_release.observability_secrets[0].values[0], "apiKeyValue")
    error_message = "No vendor secret value may appear in a Helm value"
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.datadog.api.site == "datadoghq.eu"
    error_message = "The log collector must ship to the chosen Datadog site"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters.datadog.api.site == "datadoghq.eu"
    error_message = "The metrics collector must ship to the chosen Datadog site"
  }

  # AMP and Datadog on one pipeline: the scrape happens once.
  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.metrics.exporters == ["datadog", "prometheusremotewrite/amp"]
    error_message = "Both metrics exporters must hang off the single scrape pipeline"
  }

  assert {
    condition     = output.logs_external_links[0].href_prefix == "https://app.datadoghq.eu/logs?query="
    error_message = "The Logs tab must offer an Open in Datadog link for the chosen site"
  }

  # Ship-only: Datadog never joins a rendering chain.
  assert {
    condition     = join(",", output.logs_rendering_providers) == "loki" && join(",", output.metrics_rendering_providers) == "amp"
    error_message = "A ship-only provider must not appear in a rendering chain"
  }
}

run "grafana_cloud_is_a_second_loki_write_and_a_ravion_operator_destination" {
  command = plan

  variables {
    logs_providers          = ["loki", "grafana_cloud"]
    metrics_providers       = ["grafana_cloud"]
    ravion_operator_enabled = true
    logs_grafana_cloud = {
      url              = "https://logs-prod-006.grafana.net/loki/api/v1/push"
      user             = "111111"
      token_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-cloud-token"
      stack_url        = "https://ravion.grafana.net"
    }
    metrics_grafana_cloud = {
      url  = "https://prometheus-prod-01.grafana.net/api/prom/push"
      user = "222222"
    }
  }

  # One loki.write per destination, and one file tail behind both.
  assert {
    condition     = length(regexall("loki.write \"", yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content)) == 2
    error_message = "Alloy must write to every selected loki-family destination"
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "username = \"111111\"")
    error_message = "The Grafana Cloud write must carry the tenant's user id"
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "sys.env(\"GRAFANA_CLOUD_TOKEN\")")
    error_message = "The token must be read from the environment, not written into the config"
  }

  assert {
    condition     = output.grafana_cloud_logs_query_url == "https://logs-prod-006.grafana.net/loki"
    error_message = "The logs query URL is the push URL with the push path removed"
  }

  assert {
    condition     = output.grafana_cloud_metrics_query_url == "https://prometheus-prod-01.grafana.net/api/prom"
    error_message = "The metrics query URL is the remote-write URL with the push path removed"
  }

  # Ravion Operator is the only route from Ravion to any of these.
  assert {
    condition     = contains(yamldecode(local.ravion_operator_observability_proxy_values[0]).httpProxy.allowedEndpoints, "https://logs-prod-006.grafana.net/loki")
    error_message = "Grafana Cloud's query endpoint must be on Ravion Operator's proxy allowlist"
  }

  assert {
    condition     = yamldecode(local.ravion_operator_observability_proxy_values[0]).httpProxy.credentials[0].secretName == "ravion-observability-grafana-cloud-logs"
    error_message = "Ravion Operator must be given the Secret to authenticate a proxied Grafana Cloud query with"
  }

  assert {
    condition     = yamldecode(local.ravion_operator_observability_proxy_values[0]).httpProxy.credentials[0].kind == "basic"
    error_message = "Grafana Cloud authenticates with basic auth"
  }

  assert {
    condition     = output.observability_credentials_secret_name == "ravion-observability-grafana-cloud-logs"
    error_message = "The control plane needs the name of the Secret Ravion Operator presents"
  }

  # Materialized into Ravion Operator's namespace, because a Secret cannot be mounted
  # across namespaces.
  assert {
    condition = length([
      for secret in yamldecode(helm_release.observability_secrets[0].values[0]).externalSecrets :
      secret if secret.namespace == "ravion-operator" && secret.name == "ravion-observability-grafana-cloud-metrics"
    ]) == 1
    error_message = "The proxy credential must land in Ravion Operator's namespace"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.extensions["basicauth/grafana_cloud"].client_auth.username == "222222"
    error_message = "The metrics remote write must authenticate as the Grafana Cloud instance id"
  }
}

run "new_relic_and_otlp_are_otlphttp_exporters" {
  command = plan

  variables {
    logs_providers    = ["new_relic"]
    metrics_providers = ["otlp"]
    logs_new_relic = {
      region                 = "eu"
      license_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:new-relic"
    }
    metrics_otlp = {
      endpoint = "https://api.honeycomb.io"
    }
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters["otlphttp/new_relic"].endpoint == "https://otlp.eu01.nr-data.net"
    error_message = "New Relic's EU region has its own OTLP endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlphttp/custom"].endpoint == "https://api.honeycomb.io"
    error_message = "A custom OTLP endpoint must reach the metrics collector"
  }

  # Nothing renders in Ravion here; the tabs say so rather than pretending.
  assert {
    condition     = join(",", output.logs_rendering_providers) == "" && join(",", output.metrics_rendering_providers) == ""
    error_message = "A ship-only selection has no rendering chain at all"
  }

  # kube-state-metrics is still wanted: OTLP is a metrics provider like any
  # other, and kube_* series are half of what a workload chart draws.
  assert {
    condition     = length(helm_release.kube_state_metrics) == 1
    error_message = "kube-state-metrics is installed for any metrics provider other than CloudWatch alone"
  }
}

run "cloudwatch_alone_needs_no_kube_state_metrics" {
  command = plan

  variables {
    logs_providers    = []
    metrics_providers = ["cloudwatch"]
  }

  assert {
    condition     = length(helm_release.kube_state_metrics) == 0 && length(helm_release.otel_collector) == 0
    error_message = "Container Insights collects its own metrics; a scrape pipeline beside it would be a second copy"
  }
}

################################################################################
# A vendor credential with nothing to materialize it is a collector that starts
# and then fails every export, so the plan stops instead.
################################################################################

run "vendor_provider_requires_external_secrets" {
  command = plan

  variables {
    eso_enabled       = false
    logs_providers    = ["datadog"]
    metrics_providers = []
    logs_datadog = {
      api_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:datadog-api-key"
    }
  }

  expect_failures = [helm_release.observability_secrets]
}

run "datadog_without_a_key_is_refused" {
  command = plan

  variables {
    logs_providers    = ["datadog"]
    metrics_providers = []
  }

  expect_failures = [helm_release.otel_logs_collector]
}

################################################################################
# 0.8.1 providers: OpenSearch, Splunk, and Prometheus in the cluster.
################################################################################

run "opensearch_signs_with_the_collectors_own_role" {
  command = plan

  variables {
    logs_providers    = ["opensearch"]
    metrics_providers = []
    logs_opensearch = {
      endpoint     = "https://search-logs-abc123.us-east-2.es.amazonaws.com"
      index_prefix = "ravion-eks"
    }
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.opensearch.http.endpoint == "https://search-logs-abc123.us-east-2.es.amazonaws.com"
    error_message = "The OpenSearch exporter must point at the domain endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.opensearch.logs_index == "ravion-eks"
    error_message = "The index prefix must reach the exporter"
  }

  # No key anywhere: the domain trusts an IAM role, not a password.
  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.extensions["sigv4auth/opensearch"].service == "es"
    error_message = "OpenSearch requests must be signed with SigV4 for the managed-domain service"
  }

  assert {
    condition     = output.logs_opensearch_role_arn != null
    error_message = "The role the customer maps into the domain must be published - it is the half of the grant this module cannot write"
  }

  assert {
    condition     = output.logs_external_links[0].provider == "opensearch"
    error_message = "OpenSearch ships, so the Logs tab offers a Dashboards link"
  }
}

run "splunk_ships_over_hec_with_a_referenced_token" {
  command = plan

  variables {
    logs_providers    = ["splunk"]
    metrics_providers = []
    logs_splunk = {
      hec_url              = "https://http-inputs-acme.splunkcloud.com:443/services/collector"
      hec_token_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:splunk-hec"
      index                = "kubernetes"
    }
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.splunk_hec.index == "kubernetes"
    error_message = "The target index must reach the exporter"
  }

  assert {
    condition     = yamldecode(helm_release.otel_logs_collector[0].values[0]).config.exporters.splunk_hec.token == "$${env:SPLUNK_HEC_TOKEN}"
    error_message = "The HEC token must be read from the environment, never rendered into a Helm value"
  }

  assert {
    condition     = length([for secret in local.vendor_secrets : secret if secret.provider == "splunk"]) == 1
    error_message = "The HEC token must be materialized by External Secrets"
  }
}

run "in_cluster_prometheus_is_a_rendering_provider" {
  command = plan

  variables {
    logs_providers          = []
    metrics_providers       = ["amp", "prometheus"]
    ravion_operator_enabled = true
    metrics_prometheus = {
      retention_days = 30
      storage_size   = "100Gi"
    }
  }

  assert {
    condition     = join(",", output.metrics_rendering_providers) == "amp,prometheus"
    error_message = "AMP is read first and the in-cluster store is the fallback behind it"
  }

  assert {
    condition     = length(helm_release.prometheus) == 1
    error_message = "The prometheus provider installs Prometheus unless an endpoint was given"
  }

  # Without the receiver flag every remote write from the collector is a 404.
  assert {
    condition     = contains(yamldecode(helm_release.prometheus[0].values[0]).server.extraFlags, "web.enable-remote-write-receiver")
    error_message = "Prometheus must accept remote writes, which is off by default"
  }

  assert {
    condition     = yamldecode(helm_release.prometheus[0].values[0]).server.retention == "30d" && yamldecode(helm_release.prometheus[0].values[0]).server.persistentVolume.size == "100Gi"
    error_message = "Retention and volume size must reach the chart"
  }

  assert {
    condition     = output.prometheus_endpoint == "http://ravion-prometheus-server.ravion-operator.svc.cluster.local:9090"
    error_message = "The in-cluster endpoint is what Ravion Operator proxies to and what the service modules map"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["prometheusremotewrite/in_cluster"].endpoint == "http://ravion-prometheus-server.ravion-operator.svc.cluster.local:9090/api/v1/write"
    error_message = "The collector must remote-write the same series into the in-cluster store"
  }

  # It has no route out of the cluster, so Ravion Operator is the only way to read it.
  assert {
    condition     = contains(yamldecode(local.ravion_operator_observability_proxy_values[0]).httpProxy.allowedEndpoints, "http://ravion-prometheus-server.ravion-operator.svc.cluster.local:9090")
    error_message = "The in-cluster Prometheus must be on Ravion Operator's proxy allowlist"
  }
}

run "an_existing_prometheus_skips_the_install" {
  command = plan

  variables {
    logs_providers    = []
    metrics_providers = ["prometheus"]
    metrics_prometheus = {
      endpoint = "http://prometheus.monitoring.svc.cluster.local:9090"
    }
  }

  assert {
    condition     = length(helm_release.prometheus) == 0
    error_message = "An endpoint means the customer already runs one; the module must not install a second"
  }

  assert {
    condition     = output.prometheus_endpoint == "http://prometheus.monitoring.svc.cluster.local:9090"
    error_message = "The endpoint given must be the one published and written to"
  }
}
