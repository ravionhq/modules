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
  # The CloudWatch logs provider resolves the newest observability add-on.
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v6.7.0-eksbuild.1" }
  }
  # The Pod Identity association validates the role ARN it is handed.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:mock", url = "https://sqs.us-east-2.amazonaws.com/123456789012/mock" }
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

override_resource {
  target = ravion_operator_credential.this
  values = {
    operator_agent_id = "opagt_test"
    client_id         = "client_test"
    client_secret     = "test-only-credential"
  }
}

# Every add-on this module installs must survive what took ravion-prod's
# Prometheus down for hours: being packed onto a node too small for it,
# preemption by applications, voluntary disruption mid-operation, and a single
# replica being the only copy of a controller everything depends on.

variables {
  traces_destinations                     = [{ destination = "tempo" }]
  ebs_csi_driver_enabled                  = false
  cluster_name                            = "test-cluster"
  region                                  = "us-east-2"
  cluster_security_group_id               = "sg-12345678"
  node_subnet_ids                         = ["subnet-0a", "subnet-0b"]
  karpenter_enabled                       = true
  keda_enabled                            = true
  cert_manager_enabled                    = true
  eso_enabled                             = true
  eso_allowed_namespaces                  = ["ravion-prod"]
  logs_providers                          = ["loki"]
  metrics_providers                       = ["prometheus"]
  grafana_enabled                         = true
  aws_load_balancer_controller_enabled    = true
  ravion_operator_enabled                 = true
  ravion_operator_deploy_enabled          = true
  ravion_operator_execution_jobs_enabled  = true
  ravion_operator_chart_version           = "0.5.11"
  ravion_operator_coordinator_enabled     = true
  ravion_operator_full_management_enabled = true
  ravion_operator_deploy_namespaces       = []
  system_node_count                       = 2
  system_node_labels                      = { role = "system" }
}

run "prometheus_is_sized_protected_and_given_time_to_start" {
  command = plan

  assert {
    condition     = one([for d in helm_release.prometheus[0].values : yamldecode(d).server if can(yamldecode(d).server.resources)]).resources == { requests = { cpu = "500m", memory = "7Gi" }, limits = { memory = "10Gi" } }
    error_message = "Prometheus must request the memory it uses, so Karpenter never places it on a node it will run out of."
  }
  assert {
    condition     = one([for d in helm_release.prometheus[0].values : yamldecode(d).server if can(yamldecode(d).server.resources)]).priorityClassName == "system-cluster-critical"
    error_message = "Prometheus feeds KEDA; applications must be preempted before it is."
  }
  assert {
    condition     = one([for d in helm_release.prometheus[0].values : yamldecode(d).server if can(yamldecode(d).server.resources)]).podAnnotations == { "karpenter.sh/do-not-disrupt" = "true" }
    error_message = "Karpenter must not choose to move the single Prometheus replica."
  }
  assert {
    condition     = one([for d in helm_release.prometheus[0].values : yamldecode(d).server if can(yamldecode(d).server.resources)]).startupProbe == { enabled = true, periodSeconds = 10, failureThreshold = 60, timeoutSeconds = 10 }
    error_message = "WAL replay must get ten minutes before liveness can restart Prometheus."
  }
  assert {
    condition     = yamldecode(helm_release.prometheus[0].values[0]).server.retentionSize == "40GB"
    error_message = "Local retention must be bounded below the 50Gi volume so a full disk can never crash Prometheus."
  }
  assert {
    condition     = contains(yamldecode(helm_release.prometheus[0].values[0]).server.extraFlags, "query.max-samples=30000000")
    error_message = "A single query must not be able to exhaust Prometheus' memory."
  }
  assert {
    condition     = local.thanos_sidecar.resources == { requests = { cpu = "100m", memory = "256Mi" }, limits = { memory = "1Gi" } }
    error_message = "The Thanos sidecar must have room to buffer block uploads."
  }
}

run "controllers_run_two_replicas_with_budgets_and_priority" {
  command = plan

  assert {
    condition = alltrue([
      for component in ["operator", "metricsServer", "webhooks"] :
      one([for d in helm_release.keda[0].values : yamldecode(d) if can(yamldecode(d).podDisruptionBudget)])[component].replicaCount == 2
    ])
    error_message = "Every KEDA component must run two replicas."
  }
  assert {
    condition     = one([for d in helm_release.keda[0].values : yamldecode(d) if can(yamldecode(d).podDisruptionBudget)]).podDisruptionBudget == { operator = { minAvailable = 1 }, metricServer = { minAvailable = 1 }, webhooks = { minAvailable = 1 } }
    error_message = "A drain must never take every KEDA replica at once: its metrics API backs API discovery."
  }
  assert {
    condition     = one([for d in helm_release.keda[0].values : yamldecode(d) if can(yamldecode(d).podDisruptionBudget)]).priorityClassName == "system-cluster-critical"
    error_message = "KEDA must outrank applications."
  }
  assert {
    condition = alltrue([
      for component in [
        one([for d in helm_release.cert_manager[0].values : yamldecode(d) if can(yamldecode(d).global)]),
        one([for d in helm_release.cert_manager[0].values : yamldecode(d) if can(yamldecode(d).global)]).webhook,
        one([for d in helm_release.cert_manager[0].values : yamldecode(d) if can(yamldecode(d).global)]).cainjector,
      ] : component.replicaCount == 2 && component.podDisruptionBudget == { enabled = true, minAvailable = 1 }
    ])
    error_message = "cert-manager's controller, webhook and cainjector must each run two replicas behind a budget."
  }
  assert {
    condition     = one([for d in helm_release.cert_manager[0].values : yamldecode(d) if can(yamldecode(d).global)]).global.priorityClassName == "system-cluster-critical"
    error_message = "cert-manager must outrank applications."
  }
  assert {
    condition = alltrue([
      for component in [
        one([for d in helm_release.external_secrets[0].values : yamldecode(d) if can(yamldecode(d).leaderElect)]),
        one([for d in helm_release.external_secrets[0].values : yamldecode(d) if can(yamldecode(d).leaderElect)]).webhook,
        one([for d in helm_release.external_secrets[0].values : yamldecode(d) if can(yamldecode(d).leaderElect)]).certController,
      ] : component.replicaCount == 2 && component.podDisruptionBudget == { enabled = true, minAvailable = 1 } && component.priorityClassName == "system-cluster-critical"
    ])
    error_message = "External Secrets' controller, webhook and cert controller must each run two replicas behind a budget, outranking applications."
  }
  assert {
    condition     = one([for d in helm_release.external_secrets[0].values : yamldecode(d) if can(yamldecode(d).leaderElect)]).leaderElect == true
    error_message = "Two External Secrets controllers without leader election would both reconcile."
  }
  assert {
    condition     = one([for d in helm_release.lb_controller[0].values : yamldecode(d) if can(yamldecode(d).podDisruptionBudget)]).podDisruptionBudget == { maxUnavailable = 1 }
    error_message = "The load balancer controller's webhook gates every Service; a drain must leave one replica."
  }
}

run "spread_keeps_replicas_off_a_single_node" {
  command = plan

  assert {
    condition     = one([for d in helm_release.keda[0].values : yamldecode(d) if can(yamldecode(d).podDisruptionBudget)]).topologySpreadConstraints.operator[0] == { maxSkew = 1, topologyKey = "kubernetes.io/hostname", whenUnsatisfiable = "ScheduleAnyway", labelSelector = { matchLabels = { "app.kubernetes.io/name" = "keda-operator", "app.kubernetes.io/instance" = "keda" } }, matchLabelKeys = ["pod-template-hash"] }
    error_message = "KEDA replicas must prefer distinct nodes."
  }
}

run "stores_and_collectors_outrank_applications" {
  command = plan

  assert {
    condition = alltrue([
      for values in [
        helm_release.kube_state_metrics[0].values,
        helm_release.otel_collector[0].values,
        helm_release.otlp_collector[0].values,
        helm_release.tempo[0].values,
        helm_release.grafana[0].values,
        helm_release.thanos[0].values,
      ] : anytrue([for d in values : try(yamldecode(d).priorityClassName == "system-cluster-critical", false)])
    ])
    error_message = "Stores and collectors must outrank applications."
  }
  assert {
    condition     = one([for d in helm_release.loki[0].values : yamldecode(d).singleBinary if can(yamldecode(d).singleBinary.priorityClassName)]) == { priorityClassName = "system-cluster-critical", podAnnotations = { "karpenter.sh/do-not-disrupt" = "true" } }
    error_message = "Loki's single replica must outrank applications and not be moved by Karpenter."
  }
  assert {
    condition     = one([for d in helm_release.tempo[0].values : yamldecode(d) if can(yamldecode(d).priorityClassName)]).podAnnotations == { "karpenter.sh/do-not-disrupt" = "true" }
    error_message = "Tempo's single replica must not be moved by Karpenter."
  }
  assert {
    condition     = local.otel_metrics_exporters["prometheusremotewrite/in_cluster"].retry_on_failure == { enabled = true, initial_interval = "5s", max_interval = "30s", max_elapsed_time = "600s" }
    error_message = "A Prometheus restart must not drop the samples written while it replays its WAL."
  }
}

run "node_agents_run_everywhere_first" {
  command = plan

  variables {
    logs_providers = ["loki", "cloudwatch"]
  }

  assert {
    condition     = contains(helm_release.alloy[0].values, yamlencode({ controller = { priorityClassName = "system-node-critical" } }))
    error_message = "Alloy must be scheduled on every node before applications."
  }
  assert {
    condition     = contains(helm_release.otel_logs_collector[0].values, yamlencode({ priorityClassName = "system-node-critical", tolerations = [{ operator = "Exists" }] }))
    error_message = "The logs collector must reach tainted system nodes and be scheduled before applications."
  }
}

run "thanos_query_and_store_are_highly_available" {
  command = plan

  assert {
    condition     = one([for d in helm_release.thanos[0].values : yamldecode(d) if can(yamldecode(d).query.replicas)]).query.replicas == 2 && one([for d in helm_release.thanos[0].values : yamldecode(d) if can(yamldecode(d).query.replicas)]).store.replicas == 2
    error_message = "Thanos Query sits on KEDA's path and Store serves history; each must run two replicas."
  }
  assert {
    condition     = one([for d in helm_release.thanos[0].values : yamldecode(d) if can(yamldecode(d).query.replicas)]).compactor.podAnnotations == { "karpenter.sh/do-not-disrupt" = "true" }
    error_message = "The singleton compactor must not be moved mid-compaction."
  }
}

run "karpenter_repairs_nodes_and_avoids_tiny_ones" {
  command = plan

  assert {
    condition     = one([for d in helm_release.karpenter[0].values : yamldecode(d) if can(yamldecode(d).controller)]).settings.featureGates.nodeRepair == true
    error_message = "A NotReady node must be replaced, not left holding volumes."
  }
  assert {
    condition     = one([for d in helm_release.karpenter[0].values : yamldecode(d) if can(yamldecode(d).controller)]).controller.resources == { requests = { cpu = "250m", memory = "512Mi" }, limits = { memory = "1Gi" } }
    error_message = "The Karpenter controller must request what it uses."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter[0].values[0]).settings.clusterName == "test-cluster"
    error_message = "The resilience settings must not replace the controller's own settings."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).nodePool.minInstanceMemoryMiB == 8192
    error_message = "The default NodePool must not launch nodes too small to host an add-on."
  }
}

run "disabled_resilience_leaves_the_charts_alone" {
  command = plan

  variables {
    addon_resilience_enabled = false
  }

  assert {
    condition     = !anytrue([for d in helm_release.keda[0].values : can(yamldecode(d).podDisruptionBudget)])
    error_message = "With resilience off, KEDA must keep its chart defaults."
  }
  assert {
    condition     = !anytrue([for d in helm_release.prometheus[0].values : can(yamldecode(d).server.priorityClassName)])
    error_message = "With resilience off, Prometheus must keep its chart defaults."
  }
}
