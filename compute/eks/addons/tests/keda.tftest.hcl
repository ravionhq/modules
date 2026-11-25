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
  # The metrics runs install Mimir, whose Pod Identity association needs a
  # parseable role ARN.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-cluster-observability" }
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
  traces_destinations                  = []
  ebs_csi_driver_enabled               = false
  cluster_name                         = "test-cluster"
  region                               = "us-east-2"
  cluster_security_group_id            = "sg-12345678"
  node_subnet_ids                      = ["subnet-0a", "subnet-0b"]
  karpenter_enabled                    = false
  eso_enabled                          = false
  ravion_operator_enabled              = false
  logs_providers                       = []
  metrics_providers                    = []
  aws_load_balancer_controller_enabled = false
}

run "keda_is_disabled_by_default" {
  command = plan

  assert {
    condition     = length(helm_release.keda) == 0
    error_message = "KEDA must not install unless explicitly enabled."
  }
  assert {
    condition     = output.keda_enabled == false && output.keda_namespace == null && output.keda_chart_version == null
    error_message = "Disabled KEDA outputs must reflect that no release is installed."
  }
}

run "keda_installs_the_pinned_chart_and_on_demand_components" {
  command = plan

  variables {
    keda_enabled       = true
    keda_namespace     = "keda-test"
    keda_chart_version = "2.20.2"
  }

  assert {
    condition     = helm_release.keda[0].name == "keda" && helm_release.keda[0].namespace == "keda-test" && helm_release.keda[0].repository == "https://kedacore.github.io/charts" && helm_release.keda[0].chart == "keda" && helm_release.keda[0].version == "2.20.2"
    error_message = "KEDA must use the requested namespace and pinned official chart."
  }
  assert {
    condition     = helm_release.keda[0].create_namespace && helm_release.keda[0].wait && yamldecode(helm_release.keda[0].values[0]).crds.install
    error_message = "KEDA must create its namespace, wait for readiness, and install CRDs."
  }
  assert {
    condition     = length(yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms) == 2 && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key == "eks.amazonaws.com/capacityType" && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values == ["ON_DEMAND"] && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].key == "karpenter.sh/capacity-type" && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].values == ["on-demand"]
    error_message = "KEDA controller components must stay on On-Demand managed-group or Karpenter capacity."
  }
  assert {
    condition     = output.keda_enabled && output.keda_namespace == "keda-test" && output.keda_chart_version == "2.20.2"
    error_message = "Enabled KEDA outputs must report the installed release."
  }
}

run "advanced_helm_values_override_keda_defaults" {
  command = plan

  variables {
    keda_enabled     = true
    keda_helm_values = ["crds:\n  install: false"]
  }

  assert {
    condition     = length(helm_release.keda[0].values) == 4 && yamldecode(helm_release.keda[0].values[3]).crds.install == false
    error_message = "Advanced KEDA values must be appended after defaults and take precedence."
  }
}

run "disabling_keda_removes_the_release" {
  command = plan

  variables {
    keda_enabled = false
  }

  assert {
    condition     = length(helm_release.keda) == 0 && output.keda_enabled == false
    error_message = "Disabling KEDA must remove the release and clear the enabled output."
  }
}

################################################################################
# KEDA's own metrics — collected only while KEDA and the metrics collector both
# run, from every operator replica.
################################################################################

run "keda_metrics_are_not_collected_without_a_metrics_pipeline" {
  command = plan

  variables {
    keda_enabled = true
  }

  assert {
    condition     = length(helm_release.otel_collector) == 0 && alltrue([for doc in helm_release.keda[0].values : !strcontains(doc, "keda-operator-prometheus")])
    error_message = "Without a metrics collector, KEDA must not expose a scrape Service."
  }
}

run "keda_metrics_are_not_scraped_without_keda" {
  command = plan

  variables {
    metrics_providers = ["mimir"]
  }

  assert {
    condition     = !strcontains(helm_release.otel_collector[0].values[0], "job_name: keda-operator")
    error_message = "The collector must not scrape KEDA while KEDA is not installed."
  }
}

run "keda_metrics_are_scraped_from_every_operator_replica" {
  command = plan

  variables {
    keda_enabled      = true
    keda_namespace    = "keda-test"
    metrics_providers = ["mimir"]
  }

  assert {
    condition     = yamldecode(helm_release.keda[0].values[2]).prometheus.operator.enabled && yamldecode(helm_release.keda[0].values[2]).prometheus.operator.port == 8080
    error_message = "KEDA's operator must serve Prometheus metrics on port 8080 while the collector runs."
  }

  assert {
    condition = (
      yamldecode(helm_release.keda[0].values[2]).extraObjects[0].kind == "Service" &&
      yamldecode(helm_release.keda[0].values[2]).extraObjects[0].metadata.namespace == "keda-test" &&
      yamldecode(helm_release.keda[0].values[2]).extraObjects[0].spec.clusterIP == "None" &&
      yamldecode(helm_release.keda[0].values[2]).extraObjects[0].spec.selector == { "app.kubernetes.io/name" = "keda-operator", "app.kubernetes.io/instance" = "keda" } &&
      yamldecode(helm_release.keda[0].values[2]).extraObjects[0].spec.ports[0].port == 8080
    )
    error_message = "A headless Service must select every KEDA operator pod on its metrics port, so the standby and the leader are both scraped."
  }

  assert {
    condition = anytrue([
      for job in yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.prometheus.config.scrape_configs :
      job.job_name == "keda-operator" &&
      job.dns_sd_configs[0].names == ["keda-operator-prometheus.keda-test.svc.cluster.local"] &&
      job.dns_sd_configs[0].type == "A" &&
      job.dns_sd_configs[0].port == 8080
    ])
    error_message = "The collector must discover KEDA operator pods through the headless Service's DNS records."
  }

  assert {
    condition = anytrue([
      for job in yamldecode(helm_release.otel_collector[0].values[0]).config.receivers.prometheus.config.scrape_configs :
      job.job_name == "keda-operator" && alltrue([
        for name in ["keda_scaler_metrics_value", "keda_scaler_active", "keda_scaler_detail_errors_total", "keda_scaler_errors_total", "keda_scaled_object_errors_total", "keda_scaled_object_paused", "up"] :
        can(regex("^(?:${job.metric_relabel_configs[0].regex})$", name))
      ]) && !can(regex("^(?:${job.metric_relabel_configs[0].regex})$", "keda_scaler_http_request_duration_seconds_bucket")) && !can(regex("^(?:${job.metric_relabel_configs[0].regex})$", "controller_runtime_reconcile_total"))
    ])
    error_message = "The KEDA job must keep the scaler and ScaledObject families and drop the operator's runtime and HTTP histogram series."
  }
}
