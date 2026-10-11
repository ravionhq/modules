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

# Add-ons must never all sit on one Spot node: they require On-Demand
# capacity, prefer the system node group, and tolerate CriticalAddonsOnly.
# HA coordinators on distinct nodes are pinned to the system node group,
# because the Operator chart drops affinity in that mode.

variables {
  traces_destinations                     = []
  ebs_csi_driver_enabled                  = false
  cluster_name                            = "test-cluster"
  region                                  = "us-east-2"
  cluster_security_group_id               = "sg-12345678"
  node_subnet_ids                         = ["subnet-0a", "subnet-0b"]
  karpenter_enabled                       = true
  keda_enabled                            = true
  eso_enabled                             = true
  eso_allowed_namespaces                  = ["ravion-prod"]
  logs_providers                          = []
  metrics_providers                       = []
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

run "add_ons_require_on_demand_and_prefer_the_system_group" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms == local.addon_on_demand_terms
    error_message = "KEDA must require On-Demand managed-group or Karpenter capacity."
  }
  assert {
    condition     = yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions == [{ key = "role", operator = "In", values = ["system"] }]
    error_message = "Add-ons must prefer the system node group."
  }
  assert {
    condition     = yamldecode(helm_release.keda[0].values[1]).tolerations == [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    error_message = "Add-ons must tolerate a CriticalAddonsOnly-tainted system group."
  }
}

run "external_secrets_places_all_three_deployments" {
  command = plan

  assert {
    condition = alltrue([
      for placement in [
        yamldecode(helm_release.external_secrets[0].values[1]),
        yamldecode(helm_release.external_secrets[0].values[1]).webhook,
        yamldecode(helm_release.external_secrets[0].values[1]).certController,
      ] : placement.affinity == local.addon_affinity && placement.tolerations == local.addon_tolerations
    ])
    error_message = "The ESO controller, webhook and cert controller must all get the add-on placement."
  }
}

run "distinct_coordinators_are_pinned_to_the_system_group" {
  command = plan

  assert {
    condition     = contains(helm_release.ravion_operator[0].values, yamlencode({ nodeSelector = { role = "system" }, tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }] }))
    error_message = "Coordinators on distinct nodes must be pinned to the system node group by selector."
  }
}

run "every_release_carries_the_placement" {
  command = plan

  variables {
    logs_providers                       = ["loki"]
    metrics_providers                    = ["prometheus", "amp"]
    traces_destinations                  = [{ destination = "xray" }, { destination = "tempo" }]
    grafana_enabled                      = true
    aws_load_balancer_controller_enabled = true
  }

  # Each release must carry a document with the placement at the path its
  # chart reads it from.
  assert {
    condition = alltrue([
      for values in [
        helm_release.lb_controller[0].values,
        helm_release.kube_state_metrics[0].values,
        helm_release.otel_collector[0].values,
        helm_release.otlp_collector[0].values,
        helm_release.thanos[0].values,
        helm_release.tempo[0].values,
        helm_release.grafana[0].values,
      ] : contains(values, yamlencode(local.addon_pod_placement))
    ])
    error_message = "Root-level charts must get the add-on placement at the top level."
  }
  assert {
    condition     = contains(helm_release.loki[0].values, yamlencode({ singleBinary = local.addon_pod_placement }))
    error_message = "Loki must get the add-on placement under singleBinary."
  }
  assert {
    condition     = contains(helm_release.prometheus[0].values, yamlencode({ server = local.addon_pod_placement }))
    error_message = "Prometheus must get the add-on placement under server."
  }
  assert {
    condition     = local.addon_pod_placement.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms == local.addon_on_demand_terms && local.addon_pod_placement.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions == [{ key = "role", operator = "In", values = ["system"] }] && local.addon_pod_placement.tolerations == [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    error_message = "The shared placement must require On-Demand, prefer the system group and tolerate CriticalAddonsOnly."
  }
}

run "a_single_capped_coordinator_takes_the_shared_placement" {
  command = plan

  variables {
    system_node_count = 1
  }

  assert {
    condition     = contains(helm_release.ravion_operator[0].values, yamlencode(local.addon_pod_placement))
    error_message = "Without distinct-node placement, Operator must take the shared add-on placement."
  }
}

run "no_system_labels_sets_no_preference" {
  command = plan

  variables {
    system_node_labels = {}
  }

  assert {
    condition     = !can(yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution)
    error_message = "Without system node labels there is nothing to prefer."
  }
  assert {
    condition     = contains(helm_release.ravion_operator[0].values, yamlencode(local.addon_pod_placement))
    error_message = "Without system node labels, coordinators cannot be pinned and take the shared placement."
  }
}

run "no_system_nodes_ignores_the_labels" {
  command = plan

  variables {
    system_node_count = 0
  }

  assert {
    condition     = !can(yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution)
    error_message = "A cluster without system nodes has no group to prefer."
  }
  assert {
    condition     = !anytrue([for values in helm_release.ravion_operator[0].values : can(yamldecode(values).nodeSelector)])
    error_message = "A cluster without system nodes has no group to pin coordinators to."
  }
}

run "disabled_placement_leaves_the_charts_alone" {
  command = plan

  variables {
    addon_placement_enabled = false
  }

  assert {
    condition     = length(helm_release.external_secrets[0].values) == 1 && length(helm_release.keda[0].values) == 1
    error_message = "With placement off, only the module's own values are rendered."
  }
  assert {
    condition     = yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms == local.addon_on_demand_terms
    error_message = "KEDA keeps its On-Demand requirement even with placement off."
  }
  assert {
    condition     = !anytrue([for values in helm_release.ravion_operator[0].values : can(yamldecode(values).nodeSelector) || can(yamldecode(values).tolerations)])
    error_message = "With placement off, coordinators are neither pinned nor given tolerations."
  }
}
