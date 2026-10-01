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
    traces_providers  = ["xray"]
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
    traces_providers  = ["xray"]
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
    traces_providers = ["xray"]
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
    traces_providers  = ["xray"]
    traces_xray       = { region = "us-west-2" }
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
    traces_providers = ["datadog"]
  }

  expect_failures = [var.traces_providers]
}

################################################################################
# Tempo: the in-cluster store on S3, the traces counterpart of Loki.
################################################################################

run "tempo_stores_traces_in_cluster_on_s3" {
  command = plan

  variables {
    traces_providers = ["tempo"]
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
    error_message = "Tempo's service account must carry its S3 role through Pod Identity"
  }

  assert {
    condition     = data.aws_iam_policy_document.tempo_s3[0].statement[1].resources == toset(["arn:aws:s3:::ravion-tempo-test-cluster-123456789012/*"]) && data.aws_iam_policy_document.tempo_s3[0].statement[1].actions == toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectTagging", "s3:PutObjectTagging"])
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
    traces_providers  = ["xray", "tempo"]
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
    traces_providers = ["tempo"]
    traces_tempo     = { s3_bucket_name = "my-traces", retention_days = 7 }
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
    traces_providers = ["tempo"]
    traces_tempo     = { s3_bucket_name = "" }
  }

  assert {
    condition     = length(module.tempo_bucket) == 1 && output.tempo_s3_bucket == "ravion-tempo-test-cluster-123456789012"
    error_message = "A blank bucket name must create the bucket"
  }
}

run "in_cluster_grafana_reads_tempo" {
  command = plan

  variables {
    traces_providers = ["tempo"]
    grafana_enabled  = true
  }

  assert {
    condition     = contains([for source in yamldecode(helm_release.grafana[0].values[0]).datasources["datasources.yaml"].datasources : source.uid], "ravion-tempo")
    error_message = "The in-cluster Grafana must get a Tempo data source"
  }
}

run "rejects_zero_tempo_retention" {
  command = plan

  variables {
    traces_providers = ["tempo"]
    traces_tempo     = { retention_days = 0 }
  }

  expect_failures = [var.traces_tempo]
}
