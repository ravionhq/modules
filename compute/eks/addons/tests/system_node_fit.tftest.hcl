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

# Karpenter's controller and the HA coordinators run one per system node and
# never on a Karpenter-provisioned node, and nothing can provision a node for
# them. A replica count above the system node count leaves a pod Pending
# forever and times out every Helm upgrade, so both counts fit the node group.

variables {
  cluster_name                            = "test-cluster"
  region                                  = "us-east-2"
  cluster_security_group_id               = "sg-12345678"
  node_subnet_ids                         = ["subnet-0a", "subnet-0b"]
  karpenter_enabled                       = true
  eso_enabled                             = false
  logs_providers                          = []
  metrics_providers                       = []
  ravion_operator_enabled                 = true
  ravion_operator_deploy_enabled          = true
  ravion_operator_execution_jobs_enabled  = true
  ravion_operator_chart_version           = "0.5.11"
  ravion_operator_coordinator_enabled     = true
  ravion_operator_full_management_enabled = true
  ravion_operator_deploy_namespaces       = []
}

run "no_cap_without_a_node_count" {
  command = plan
  assert {
    condition     = yamldecode(helm_release.karpenter[0].values[0]).replicas == 2
    error_message = "Without a node count, Karpenter keeps its two-replica default."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 2 && yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes
    error_message = "Without a node count, coordinators keep the configured count and placement."
  }
}

run "one_system_node_runs_one_of_each" {
  command = plan
  variables {
    system_node_count = 1
  }
  assert {
    condition     = yamldecode(helm_release.karpenter[0].values[0]).replicas == 1
    error_message = "One system node fits one Karpenter controller."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 1
    error_message = "One system node fits one coordinator."
  }
  assert {
    condition     = !yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes
    error_message = "A single capped coordinator must be able to surge its self-update onto the same node."
  }
}

run "two_or_more_system_nodes_keep_high_availability" {
  command = plan
  variables {
    system_node_count = 3
  }
  assert {
    condition     = yamldecode(helm_release.karpenter[0].values[0]).replicas == 2
    error_message = "Karpenter never runs more than two controllers."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 2 && yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes
    error_message = "With enough nodes, coordinators keep the configured count on distinct nodes."
  }
}

run "zero_system_nodes_still_runs_one" {
  command = plan
  variables {
    system_node_count = 0
  }
  assert {
    condition     = yamldecode(helm_release.karpenter[0].values[0]).replicas == 1 && yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 1
    error_message = "A controller must always be requested; it waits for a node rather than disappearing."
  }
}

run "explicit_single_coordinator_on_distinct_nodes_is_still_refused" {
  command = plan
  variables {
    ravion_operator_coordinator_replicas = 1
  }
  expect_failures = [helm_release.ravion_operator]
}
