################################################################################
# Workload metrics, Container Insights trim, and Grafana read role
#
# Toggle matrix for the observability half of this module. Run from the module
# root: `tofu test`.
#
# Karpenter and the External Secrets Operator are off in every run: they pull in
# submodules and Helm releases that have nothing to do with what is asserted
# here, and leaving them on only slows the plan down.
#
# The logs pipeline has its own file, logs.tftest.hcl.
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
# Metrics off — the default. Nothing new is rendered, and the Container Insights
# add-on is left exactly as it was before this feature existed.
################################################################################

run "metrics_disabled_renders_nothing" {
  command = plan

  assert {
    condition     = length(aws_prometheus_workspace.this) == 0
    error_message = "No AMP workspace may be created while metrics_enabled is false"
  }

  assert {
    condition     = length(helm_release.otel_collector) == 0 && length(helm_release.kube_state_metrics) == 0
    error_message = "Neither the collector nor kube-state-metrics may be installed while metrics_enabled is false"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.otel_collector) == 0
    error_message = "No collector Pod Identity association may exist while metrics_enabled is false"
  }

  assert {
    condition     = output.amp_workspace_id == null && output.amp_workspace_arn == null && output.amp_remote_write_endpoint == null && output.amp_query_endpoint == null && output.amp_region == null
    error_message = "Every AMP output must be null while metrics_enabled is false"
  }

  # Container Insights is a legacy toggle now, not the log pipeline, so it is
  # off unless someone asks for it.
  assert {
    condition     = length(aws_eks_addon.cloudwatch_observability) == 0
    error_message = "The amazon-cloudwatch-observability add-on must be off by default"
  }

  assert {
    condition     = output.grafana_role_arn == null
    error_message = "The Grafana read role is off by default"
  }
}

################################################################################
# Metrics on — workspace, IAM, both Helm releases, and the log-contract outputs.
################################################################################

run "metrics_enabled_creates_workspace_and_collector" {
  command = plan

  variables {
    metrics_providers = ["amp"]
  }

  assert {
    condition     = length(aws_prometheus_workspace.this) == 1
    error_message = "metrics_enabled with no amp_workspace_id must create a workspace"
  }

  assert {
    condition     = aws_prometheus_workspace.this[0].alias == "ravion-test-cluster"
    error_message = "The created workspace must be aliased ravion-<cluster_name>"
  }

  assert {
    condition     = length(helm_release.otel_collector) == 1 && length(helm_release.kube_state_metrics) == 1
    error_message = "metrics_enabled must install the collector and kube-state-metrics"
  }

  # Both land in Ravion Operator's namespace: one namespace for Ravion's in-cluster
  # components, which is what metrics_namespace overrides.
  assert {
    condition     = helm_release.otel_collector[0].namespace == "ravion-operator" && helm_release.kube_state_metrics[0].namespace == "ravion-operator"
    error_message = "Metrics components default to Ravion Operator's namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.otel_collector[0].service_account == var.otel_collector_service_account
    error_message = "The Pod Identity association must bind to the collector's service account"
  }
}

################################################################################
# Bring your own workspace — creation is suppressed and every derived value
# still resolves, because nothing downstream branches on which case it is.
################################################################################

run "byo_workspace_suppresses_creation" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    amp_workspace_id  = "ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition     = length(aws_prometheus_workspace.this) == 0
    error_message = "An explicit amp_workspace_id must suppress workspace creation"
  }

  assert {
    condition     = output.amp_workspace_id == "ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "The bring-your-own workspace id must flow through to the output"
  }

  assert {
    condition     = output.amp_workspace_arn == "arn:aws:aps:us-east-2:123456789012:workspace/ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "The workspace ARN must be constructed from partition, region, account, and id"
  }

  assert {
    condition     = output.amp_remote_write_endpoint == "https://aps-workspaces.us-east-2.amazonaws.com/workspaces/ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/api/v1/remote_write"
    error_message = "The remote-write endpoint must be derived from the workspace region and id"
  }

  # Scoped to this one workspace, not aps:* — the whole point of the role.
  assert {
    condition     = data.aws_iam_policy_document.amp_remote_write[0].statement[0].actions == toset(["aps:RemoteWrite"])
    error_message = "The collector role must grant aps:RemoteWrite and nothing else"
  }

  assert {
    condition     = data.aws_iam_policy_document.amp_remote_write[0].statement[0].resources == toset([output.amp_workspace_arn])
    error_message = "The collector role must be scoped to the single workspace ARN"
  }
}

################################################################################
# A workspace in another region — for clusters where AMP is not available.
################################################################################

run "amp_region_override_moves_the_endpoint" {
  command = plan

  variables {
    metrics_providers = ["amp"]
    amp_workspace_id  = "ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    amp_region        = "us-west-2"
  }

  assert {
    condition     = output.amp_region == "us-west-2"
    error_message = "amp_region must override the cluster's region"
  }

  assert {
    condition     = strcontains(output.amp_remote_write_endpoint, "aps-workspaces.us-west-2.amazonaws.com")
    error_message = "The remote-write endpoint must follow amp_region"
  }

  assert {
    condition     = yamldecode(helm_release.otel_collector[0].values[0]).config.extensions.sigv4auth.region == "us-west-2"
    error_message = "The sigv4auth extension must sign for the workspace's region, not the cluster's"
  }
}

################################################################################
# Allow-list composition — the base set is present, additions are appended to
# every job, and the cAdvisor label drop survives templating.
################################################################################

run "allowlist_composition" {
  command = plan

  variables {
    metrics_providers            = ["amp"]
    metrics_additional_allowlist = ["my_app_requests_total", "my_app_.*_seconds"]
    scrape_interval_seconds      = 120
  }

  assert {
    condition     = strcontains(helm_release.otel_collector[0].values[0], "container_cpu_usage_seconds_total|container_cpu_cfs_throttled_periods_total")
    error_message = "The cAdvisor keep regex must carry the curated base list, in order"
  }

  assert {
    condition     = strcontains(helm_release.otel_collector[0].values[0], "kube_pod_container_status_restarts_total")
    error_message = "The kube-state-metrics keep regex must carry the curated base list"
  }

  assert {
    condition     = strcontains(helm_release.otel_collector[0].values[0], "node_cpu_usage_seconds_total|node_memory_working_set_bytes|up")
    error_message = "The kubelet resource keep regex must carry its base list plus up"
  }

  # Appended to every job, because a user's metric may come from any of them.
  assert {
    condition = length([
      for line in split("\n", helm_release.otel_collector[0].values[0]) :
      line if strcontains(line, "my_app_requests_total|my_app_.*_seconds")
    ]) == 3
    error_message = "metrics_additional_allowlist must be appended to all three scrape jobs"
  }

  assert {
    condition     = strcontains(helm_release.otel_collector[0].values[0], "regex: id|name|image")
    error_message = "cAdvisor's id/name/image labels must be dropped"
  }

  assert {
    condition     = length(regexall("scrape_interval: 120s", helm_release.otel_collector[0].values[0])) == 3
    error_message = "scrape_interval_seconds must reach every scrape job"
  }
}

run "kube_state_metrics_can_be_left_out" {
  command = plan

  variables {
    metrics_providers          = ["amp"]
    kube_state_metrics_enabled = false
  }

  assert {
    condition     = length(helm_release.kube_state_metrics) == 0
    error_message = "kube_state_metrics_enabled = false must skip the release"
  }

  assert {
    condition     = !strcontains(helm_release.otel_collector[0].values[0], "job_name: kube-state-metrics")
    error_message = "With no kube-state-metrics installed, the collector must not scrape it"
  }
}

################################################################################
# Grafana read role.
################################################################################

run "grafana_role_scoping" {
  command = plan

  variables {
    metrics_providers             = ["amp"]
    amp_workspace_id              = "ws-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    grafana_role_creation_enabled = true
  }

  assert {
    condition     = length(data.aws_iam_policy_document.grafana_read[0].statement) == 3
    error_message = "With metrics on the role carries the workspace query, log read, and query-results statements"
  }

  assert {
    condition     = data.aws_iam_policy_document.grafana_read[0].statement[0].resources == toset([output.amp_workspace_arn])
    error_message = "Grafana's PromQL grant must be scoped to this workspace"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.grafana_read[0].statement[1].resources, "arn:aws:logs:us-east-2:123456789012:log-group:/aws/containerinsights/test-cluster/*")
    error_message = "Grafana's log grant must be scoped to this cluster's Container Insights groups"
  }

  assert {
    condition     = output.grafana_role_arn != null
    error_message = "grafana_role_creation_enabled must produce a role ARN"
  }
}

run "grafana_role_without_metrics_carries_logs_only" {
  command = plan

  variables {
    grafana_role_creation_enabled = true
  }

  assert {
    condition     = length(data.aws_iam_policy_document.grafana_read[0].statement) == 2
    error_message = "With metrics off there is no workspace to grant against, so only the log statements render"
  }
}
