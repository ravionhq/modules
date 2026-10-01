################################################################################
# OTLP from workloads: the collector's receiver, X-Ray traces, OTLP metrics
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

# Both signals start empty so every run opts into exactly the providers it is
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

run "otlp_off_by_default" {
  command = plan

  variables {
    metrics_providers = ["amp"]
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).service.enabled == false
    error_message = "The collector must have no Service while the OTLP receiver is off"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.otlp == null && yamldecode(helm_release.otel_collector[0].values[0]).config.service.pipelines.traces == null
    error_message = "No OTLP receiver or traces pipeline may run while the OTLP receiver is off"
  }

  assert {
    condition     = length(aws_iam_role_policy.otel_collector_xray) == 0 && length(module.otel_collector_role) == 0
    error_message = "No X-Ray permission may exist while the OTLP receiver is off"
  }

  assert {
    condition     = output.otlp_host == null && output.otlp_grpc_endpoint == null && output.otlp_http_endpoint == null && output.xray_region == null
    error_message = "The OTLP outputs must be null while the OTLP receiver is off"
  }
}

################################################################################
# On, with AMP: X-Ray write joins the remote-write role.
################################################################################

run "otlp_with_amp_sends_traces_to_xray_and_metrics_to_amp" {
  command = plan

  variables {
    metrics_providers     = ["amp"]
    otlp_receiver_enabled = true
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
    error_message = "The OTLP outputs must name the collector's in-cluster Service"
  }
}

################################################################################
# On, without AMP: the collector gets an X-Ray role of its own.
################################################################################

run "otlp_without_amp_gets_its_own_role" {
  command = plan

  variables {
    metrics_providers     = ["prometheus"]
    otlp_receiver_enabled = true
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
# Requested while metrics are off: there is no collector to receive on.
################################################################################

run "otlp_needs_metrics_on" {
  command = plan

  variables {
    otlp_receiver_enabled = true
  }

  assert {
    condition     = length(helm_release.otel_collector) == 0 && length(aws_eks_pod_identity_association.otel_collector) == 0
    error_message = "The OTLP receiver must not install a collector on its own"
  }

  assert {
    condition     = output.otlp_grpc_endpoint == null && output.otlp_http_endpoint == null
    error_message = "The OTLP outputs must be null while metrics are off"
  }
}
