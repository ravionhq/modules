################################################################################
# Traces: the collector's OTLP receiver, X-Ray, and workload OTLP metrics
#
# Toggle matrix for the observability half of this module. Run from the module
# root: `tofu test`.
#
# Karpenter and the External Secrets Operator are off in every run: they pull in
# submodules and Helm releases that have nothing to do with what is asserted
# here, and leaving them on only slows the plan down.
#
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

# Ravion Operator's credential is minted by Ravion's own provider, which refuses to
# configure without a runner JWT.
mock_provider "ravion" {}

# Every signal starts empty so each run opts into exactly the providers it is
# about. The defaults ([loki] and [amp]) have their own coverage in
# observability.tftest.hcl.
variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = false
  logs_providers    = []
  metrics_providers = []
}

################################################################################
# Off by default: the collector keeps pulling only, with no Service.
################################################################################

run "traces_off_by_default" {
  command = plan

  variables {
    metrics_providers = ["amp"]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).service.enabled == false
    error_message = "The collector must have no Service while traces are off"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.otlp == null && yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces == null
    error_message = "No OTLP receiver or traces pipeline may run while traces are off"
  }

  assert {
    condition     = length(aws_iam_role_policy.otel_collector_xray) == 0 && length(module.otel_collector_role) == 0
    error_message = "No X-Ray permission may exist while traces are off"
  }

  assert {
    condition     = output.otlp_host == null && output.otlp_grpc_endpoint == null && output.otlp_http_endpoint == null && output.xray_region == null
    error_message = "The traces outputs must be null while traces are off"
  }
}

################################################################################
# X-Ray with AMP: X-Ray write joins the remote-write role.
################################################################################

run "xray_with_amp_sends_traces_to_xray_and_workload_metrics_to_amp" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    traces_destinations = [
      { destination = "xray" },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).service.enabled == true && yamldecode(helm_release.otel_collector[0].values[0]).ports.otlp.enabled == true && yamldecode(helm_release.otel_collector[0].values[0])["ports"]["otlp-http"].enabled == true
    error_message = "The collector must expose both OTLP ports through a Service"
  }

  assert {
    condition     = keys(yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.otlp.protocols) == ["grpc", "http"]
    error_message = "The OTLP receiver must accept gRPC and HTTP"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["awsxray"] && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters.awsxray.region == "us-east-2"
    error_message = "Workload traces must go to X-Ray in the cluster's region"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines["metrics/otlp"].exporters == ["prometheusremotewrite/amp"] && yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines["metrics/otlp"].receivers == ["otlp"]
    error_message = "Workload metrics must go to the same destinations as the scraped ones"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.metrics.receivers == ["prometheus"]
    error_message = "The scrape pipeline must stay prometheus-only"
  }

  assert {
    condition     = length(aws_iam_role_policy.otel_collector_xray) == 1 && length(module.otel_collector_role) == 0 && length(aws_eks_pod_identity_association.otel_collector) == 1
    error_message = "With AMP, X-Ray write must join the remote-write role behind the one association"
  }

  assert {
    condition     = data.aws_iam_policy_document.otel_collector_xray[0].statement[0].actions == toset(["xray:PutTraceSegments", "xray:PutTelemetryRecords"])
    error_message = "The collector may only write to X-Ray"
  }

  assert {
    condition     = output.otlp_host == "ravion-otel-collector.ravion-operator.svc.cluster.local" && output.otlp_grpc_endpoint == "http://ravion-otel-collector.ravion-operator.svc.cluster.local:4317" && output.otlp_http_endpoint == "http://ravion-otel-collector.ravion-operator.svc.cluster.local:4318" && output.xray_region == "us-east-2"
    error_message = "The traces outputs must name the collector's in-cluster Service"
  }
}

################################################################################
# X-Ray without AMP: the collector gets an X-Ray role of its own.
################################################################################

run "xray_without_amp_gets_its_own_role" {
  command = plan

  variables {
    metrics_providers = ["prometheus"]
    traces_destinations = [
      { destination = "xray" },
    ]
  }

  assert {
    condition     = length(module.otel_collector_role) == 1 && length(aws_iam_role_policy.otel_collector_xray) == 0 && length(aws_eks_pod_identity_association.otel_collector) == 1
    error_message = "Without AMP, the collector's association must carry an X-Ray-only role"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines["metrics/otlp"].exporters == ["prometheusremotewrite/in_cluster"]
    error_message = "Workload metrics must go to the in-cluster Prometheus"
  }
}

################################################################################
# Traces with metrics off: the collector runs for traces alone.
################################################################################

run "traces_without_metrics_run_a_traces_only_collector" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "xray" },
    ]
  }

  assert {
    condition     = length(helm_release.otel_collector) == 1 && length(helm_release.kube_state_metrics) == 0
    error_message = "Traces alone must run the collector, and nothing that only metrics need"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.prometheus == null && yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.metrics == null && !contains(keys(yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines), "metrics/otlp")
    error_message = "A traces-only collector must neither scrape nor take workload metrics"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).clusterRole.create == false
    error_message = "A traces-only collector must not get the node read permissions the scrape needs"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["awsxray"] && yamldecode(helm_release.otel_collector[0].values[0]).service.enabled == true
    error_message = "A traces-only collector must still receive OTLP and export to X-Ray"
  }

  assert {
    condition     = length(module.otel_collector_role) == 1 && length(aws_eks_pod_identity_association.otel_collector) == 1 && length(aws_prometheus_workspace.this) == 0
    error_message = "A traces-only collector must get its X-Ray role and no AMP workspace"
  }

  assert {
    condition     = output.otlp_grpc_endpoint == "http://ravion-otel-collector.ravion-operator.svc.cluster.local:4317" && output.xray_region == "us-east-2"
    error_message = "The traces outputs must be set with metrics off"
  }
}

################################################################################
# Another X-Ray region.
################################################################################

run "xray_region_can_differ_from_the_cluster" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    traces_destinations = [
      {
        destination = "xray"
        region      = "us-west-2"
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters.awsxray.region == "us-west-2" && output.xray_region == "us-west-2"
    error_message = "Traces must go to the X-Ray region that was set"
  }
}

################################################################################
# Only known destinations.
################################################################################

run "rejects_unknown_traces_provider" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "zipkin" },
    ]
  }

  expect_failures = [var.traces_destinations]
}

################################################################################
# Tempo: the in-cluster store on S3, the traces counterpart of Loki.
################################################################################

run "tempo_stores_traces_in_cluster_on_s3" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo" },
    ]
  }

  assert {
    condition     = length(module.tempo_bucket) == 1 && output.tempo_s3_bucket == "ravion-tempo-test-cluster-123456789012"
    error_message = "Tempo must get a bucket named ravion-tempo-<cluster>-<account>"
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.backend == "s3" && yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.s3.bucket == "ravion-tempo-test-cluster-123456789012" && yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.s3.region == "us-east-2"
    error_message = "Tempo must store its blocks in the trace bucket"
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.retention == "720h"
    error_message = "Traces must stay queryable for 30 days by default"
  }

  assert {
    condition     = !contains(keys(yamldecode(helm_release.tempo[0].values[0]).tempo), "receivers")
    error_message = "Tempo must keep the chart's receivers: its Service template fails to render without the Jaeger ones"
  }

  assert {
    condition     = length(module.tempo_role) == 1 && aws_eks_pod_identity_association.tempo[0].service_account == "ravion-tempo" && aws_eks_pod_identity_association.tempo[0].namespace == "ravion-operator" && yamldecode(helm_release.tempo[0].values[0]).serviceAccount.name == "ravion-tempo"
    error_message = "Tempo's service account must carry its role through Pod Identity"
  }

  assert {
    condition     = data.aws_iam_policy_document.tempo[0].statement[1].resources == toset(["arn:aws:s3:::ravion-tempo-test-cluster-123456789012/*"]) && data.aws_iam_policy_document.tempo[0].statement[1].actions == toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectTagging", "s3:PutObjectTagging"])
    error_message = "Tempo's role must have Tempo's documented object permissions on its own bucket only"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["otlp/tempo"] && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlp/tempo"].endpoint == "ravion-tempo.ravion-operator.svc.cluster.local:4317"
    error_message = "The collector must send traces to Tempo's in-cluster Service"
  }

  assert {
    condition     = length(module.otel_collector_role) == 0 && length(aws_iam_role_policy.otel_collector_xray) == 0 && output.xray_region == null
    error_message = "Tempo alone needs no X-Ray permission"
  }

  assert {
    condition     = output.tempo_endpoint == "http://ravion-tempo.ravion-operator.svc.cluster.local:3200"
    error_message = "The Tempo query endpoint must name its in-cluster Service"
  }
}

run "xray_and_tempo_both_receive_every_trace" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    traces_destinations = [
      { destination = "xray" },
      { destination = "tempo" },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["awsxray", "otlp/tempo"]
    error_message = "With both providers, the traces pipeline must fan out to X-Ray and Tempo"
  }

  assert {
    condition     = length(aws_iam_role_policy.otel_collector_xray) == 1 && length(helm_release.tempo) == 1
    error_message = "Both stores must be set up"
  }
}

run "tempo_uses_an_existing_bucket_and_retention" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo", s3_bucket_name = "my-traces", retention_days = 7 },
    ]
  }

  assert {
    condition     = length(module.tempo_bucket) == 0 && yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.s3.bucket == "my-traces"
    error_message = "An existing bucket must be used as is, without creating one"
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.retention == "168h"
    error_message = "Retention must follow traces_tempo.retention_days"
  }
}

run "tempo_creates_a_bucket_when_the_form_leaves_it_blank" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo", s3_bucket_name = "" },
    ]
  }

  assert {
    condition     = length(module.tempo_bucket) == 1 && output.tempo_s3_bucket == "ravion-tempo-test-cluster-123456789012"
    error_message = "A blank bucket name must create the bucket"
  }
}

run "in_cluster_grafana_reads_tempo" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo" },
    ]
    grafana_enabled = true
  }

  assert {
    condition     = contains([for source in yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources : source.uid], "ravion-tempo")
    error_message = "The in-cluster Grafana must get a Tempo data source"
  }
}

run "rejects_zero_tempo_retention" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination    = "tempo"
        retention_days = 0
      },
    ]
  }

  expect_failures = [var.traces_destinations]
}

run "tempo_keeps_blocks_on_its_own_volume_without_aws_access" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination         = "tempo"
        storage_backend     = "local"
        persistence_enabled = true
        persistence_size    = "50Gi"
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.backend == "local" && yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.local.path == "/var/tempo/traces" && !contains(keys(yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace), "s3")
    error_message = "Local storage must keep blocks on Tempo's volume, with no S3 settings"
  }

  assert {
    condition     = length(module.tempo_role) == 0 && length(aws_eks_pod_identity_association.tempo) == 0 && output.tempo_s3_bucket == null && output.tempo_role_arn == null
    error_message = "Local storage needs no AWS role, and no bucket in use"
  }

  assert {
    condition     = length(module.tempo_bucket) == 1
    error_message = "The created bucket must survive a switch to local storage, so no stored trace is deleted"
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).persistence.enabled == true && yamldecode(helm_release.tempo[0].values[0]).persistence.size == "50Gi" && length(yamldecode(helm_release.tempo[0].values[0]).extraVolumes) == 0 && length(yamldecode(helm_release.tempo[0].values[0]).tempo.extraVolumeMounts) == 0
    error_message = "With persistence, Tempo's volume must be the chart's claim, not an emptyDir"
  }
}

run "tempo_uses_a_size_limited_scratch_volume_by_default" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo" },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).persistence.enabled == false && yamldecode(helm_release.tempo[0].values[0]).extraVolumes[0].emptyDir.sizeLimit == "10Gi" && yamldecode(helm_release.tempo[0].values[0]).tempo.extraVolumeMounts[0].mountPath == "/var/tempo"
    error_message = "Without persistence, Tempo's volume must be a 10Gi emptyDir at /var/tempo"
  }

  assert {
    condition     = !contains(keys(yamldecode(helm_release.tempo[0].values[0]).tempo), "metricsGenerator") && length(helm_release.tempo[0].values) == 1
    error_message = "The metrics generator and extra values must be off by default"
  }
}

run "tempo_metrics_generator_writes_to_the_in_cluster_prometheus" {
  command = plan

  variables {
    metrics_providers = ["prometheus"]
    traces_destinations = [
      {
        destination               = "tempo"
        metrics_generator_enabled = true
      },
    ]
    grafana_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.metricsGenerator.enabled == true && yamldecode(helm_release.tempo[0].values[0]).tempo.metricsGenerator.storage.remote_write[0].url == "http://ravion-prometheus-server.ravion-operator.svc.cluster.local:9090/api/v1/write" && !contains(keys(yamldecode(helm_release.tempo[0].values[0]).tempo.metricsGenerator.storage.remote_write[0]), "sigv4")
    error_message = "The generator must remote-write to the in-cluster Prometheus, unsigned"
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.overrides.defaults.metrics_generator.processors == ["service-graphs", "span-metrics"]
    error_message = "The generator must run the service graph and span metrics processors"
  }

  assert {
    condition     = one([for source in yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources : source if source.uid == "ravion-tempo"]).jsonData.serviceMap.datasourceUid == "ravion-prometheus"
    error_message = "Grafana's Tempo data source must draw its service map from Prometheus"
  }
}

run "tempo_metrics_generator_signs_its_writes_to_amp" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    traces_destinations = [
      {
        destination               = "tempo"
        storage_backend           = "local"
        metrics_generator_enabled = true
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.metricsGenerator.storage.remote_write[0].sigv4.region == "us-east-2"
    error_message = "Writes to AMP must be signed with SigV4"
  }

  assert {
    condition     = length(module.tempo_role) == 1 && length(aws_eks_pod_identity_association.tempo) == 1 && one([for statement in data.aws_iam_policy_document.tempo[0].statement : statement if statement.sid == "WriteGeneratedMetrics"]).actions == toset(["aps:RemoteWrite"])
    error_message = "With local storage, Tempo's role must exist for AMP remote write only"
  }
}

run "tempo_takes_any_chart_values" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination = "tempo"
        helm_values = {
          replicas = 2
          tempo = {
            overrides = {
              defaults = {
                global = {
                  max_bytes_per_trace = 10000000
                }
              }
            }
          }
        }
      },
    ]
  }

  assert {
    condition     = length(helm_release.tempo[0].values) == 2 && yamldecode(helm_release.tempo[0].values[1]).replicas == 2 && yamldecode(helm_release.tempo[0].values[1]).tempo.overrides.defaults.global.max_bytes_per_trace == 10000000
    error_message = "A tempo destination's helm_values must reach the chart after the module's own values"
  }
}

run "rejects_a_generator_with_nowhere_to_write" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination               = "tempo"
        metrics_generator_enabled = true
      },
    ]
  }

  expect_failures = [helm_release.tempo]
}

run "rejects_unknown_tempo_storage" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination     = "tempo"
        storage_backend = "gcs"
      },
    ]
  }

  expect_failures = [var.traces_destinations]
}

run "rejects_tempo_helm_values_that_are_not_an_object" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination = "tempo"
        helm_values = "replicas: 2"
      },
    ]
  }

  expect_failures = [var.traces_destinations]
}

run "tempo_bucket_name_fits_s3_for_a_long_cluster_name" {
  command = plan

  variables {
    cluster_name                = "a-very-long-cluster-name-that-fills-the-slug-entirely"
    public_alb_creation_enabled = false
    traces_destinations = [
      { destination = "tempo" },
    ]
  }

  assert {
    condition     = length(output.tempo_s3_bucket) <= 63 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", output.tempo_s3_bucket)) && !strcontains(output.tempo_s3_bucket, "--")
    error_message = "Tempo's generated bucket name must be a valid S3 name of at most 63 characters"
  }
}

run "traces_go_to_every_vendor_destination" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["apps"]
    traces_destinations = [
      {
        destination      = "grafana_cloud"
        url              = "https://otlp-gateway-prod-us-east-0.grafana.net/otlp"
        user             = "123456"
        token_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-cloud-AbCdEf"
      },
      {
        destination        = "datadog"
        site               = "datadoghq.eu"
        api_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:datadog-AbCdEf"
      },
      {
        destination            = "new_relic"
        new_relic_region       = "eu"
        license_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:new-relic-AbCdEf"
      },
      {
        destination        = "otlp"
        endpoint           = "https://api.honeycomb.io"
        headers_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:honeycomb-AbCdEf"
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["datadog", "otlp_http/custom_traces", "otlp_http/grafana_cloud_traces", "otlp_http/new_relic"]
    error_message = "The traces pipeline must send to each selected vendor"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlp_http/grafana_cloud_traces"].endpoint == "https://otlp-gateway-prod-us-east-0.grafana.net/otlp" && yamldecode(helm_release.otel_collector[0].values[0]).config.extensions["basicauth/grafana_cloud_traces"].client_auth.username == "123456" && contains(yamldecode(helm_release.otel_collector[0].values[0]).config.service.extensions, "basicauth/grafana_cloud_traces")
    error_message = "Grafana Cloud traces must authenticate with the traces instance id"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.exporters.datadog.api.site == "datadoghq.eu" && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlp_http/new_relic"].endpoint == "https://otlp.eu01.nr-data.net" && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlp_http/custom_traces"].endpoint == "https://api.honeycomb.io" && yamldecode(helm_release.otel_collector[0].values[0]).config.exporters["otlp_http/custom_traces"].headers.authorization == "$${env:OTLP_TRACES_AUTHORIZATION}"
    error_message = "Each vendor exporter must carry its own site, region or endpoint"
  }

  assert {
    condition     = toset([for env in yamldecode(helm_release.otel_collector[0].values[0]).extraEnvs : env.name]) == toset(["DATADOG_API_KEY", "NEW_RELIC_LICENSE_KEY", "GRAFANA_CLOUD_TOKEN", "OTLP_TRACES_AUTHORIZATION"])
    error_message = "Each vendor's secret must reach the collector as an environment variable"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).image.repository == "docker.io/otel/opentelemetry-collector-contrib"
    error_message = "Vendor trace destinations need the contrib collector"
  }
}

run "a_vendor_account_is_one_exporter_for_metrics_and_traces" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["apps"]
    metrics_providers      = ["prometheus", "datadog"]
    traces_destinations = [
      { destination = "tempo" },
      { destination = "datadog" },
    ]
    metrics_datadog = {
      api_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:datadog-AbCdEf"
    }
  }

  assert {
    condition     = contains(yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters, "datadog") && contains(yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.metrics.exporters, "datadog")
    error_message = "Both signals must reach Datadog through the shared exporter and key"
  }
}

run "traces_only_vendors_stay_out_of_the_metrics_pipeline" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["apps"]
    metrics_providers      = ["prometheus"]
    traces_destinations = [
      {
        destination            = "new_relic"
        license_key_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:new-relic-AbCdEf"
      },
    ]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.metrics.exporters == ["prometheusremotewrite/in_cluster"] && yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces.exporters == ["otlp_http/new_relic"]
    error_message = "A traces destination must not receive metrics"
  }
}

run "rejects_grafana_cloud_traces_without_its_instance" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["apps"]
    traces_destinations = [
      {
        destination      = "grafana_cloud"
        url              = "https://otlp-gateway-prod-us-east-0.grafana.net/otlp"
        token_secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:grafana-cloud-AbCdEf"
      },
    ]
  }

  expect_failures = [helm_release.otel_collector]
}

run "rejects_otlp_traces_without_an_endpoint" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "otlp" },
    ]
  }

  expect_failures = [helm_release.otel_collector]
}

run "tempo_follows_persistence_set_in_chart_values" {
  command = plan

  variables {
    traces_destinations = [
      {
        destination = "tempo"
        helm_values = {
          persistence = {
            enabled = true
          }
        }
      },
    ]
  }

  assert {
    condition     = terraform_data.tempo_volume_kind[0].input == true && length(yamldecode(helm_release.tempo[0].values[0]).extraVolumes) == 0 && length(yamldecode(helm_release.tempo[0].values[0]).tempo.extraVolumeMounts) == 0
    error_message = "Persistence turned on in chart values must drive the reinstall and drop the scratch volume"
  }
}

run "tempo_follows_the_last_values_document" {
  command = plan

  variables {
    traces_destinations = [
      { destination = "tempo", persistence_enabled = true },
    ]
    tempo_helm_values = ["persistence:\n  enabled: false\n"]
  }

  assert {
    condition     = terraform_data.tempo_volume_kind[0].input == false && yamldecode(helm_release.tempo[0].values[0]).extraVolumes[0].name == "tempo-data"
    error_message = "A later values document turning persistence off must win, as it does in Helm"
  }
}
