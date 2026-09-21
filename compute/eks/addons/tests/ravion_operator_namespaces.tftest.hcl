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

variables {
  cluster_name                      = "test-cluster"
  region                            = "us-east-2"
  karpenter_enabled                 = false
  eso_enabled                       = false
  logs_providers                    = []
  metrics_providers                 = []
  ravion_operator_enabled           = true
  ravion_operator_deploy_enabled    = true
  ravion_operator_deploy_namespaces = ["rvn-app", "rvn-app"]
}

run "bootstrap_deployment_namespaces" {
  command = plan
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["rvn-app"]
    error_message = "Apply must bootstrap the configured deployment namespace once."
  }
  assert {
    condition     = helm_release.ravion_operator_namespaces[0].namespace == "kube-system"
    error_message = "Namespace bootstrap must not move when the Operator namespace changes."
  }
  assert {
    condition     = helm_release.ravion_operator[0].namespace == "ravion-operator" && helm_release.ravion_operator_credential[0].namespace == "ravion-operator"
    error_message = "The agent and its credential must share the new default namespace."
  }
}

run "bootstrap_observation_and_deployment_namespaces" {
  command = plan
  variables {
    ravion_operator_namespace_scope = ["observed", "rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed", "rvn-app"]
    error_message = "Both observation and deployment RBAC require existing namespaces."
  }
}

run "deployment_scope_fallback" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = []
    ravion_operator_namespace_scope   = ["observed"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed"]
    error_message = "Bootstrap must follow the chart's observation-scope fallback."
  }
}

run "no_deployment_namespaces_when_deploy_disabled" {
  command = plan
  variables {
    ravion_operator_deploy_enabled = false
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0
    error_message = "Unused deployment namespaces must not be created."
  }
}

run "externally_provisioned_namespaces" {
  command = plan
  variables {
    ravion_operator_namespaces_creation_enabled = false
    ravion_operator_namespace                   = "existing-agent"
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0 && helm_release.ravion_operator[0].namespace == "existing-agent"
    error_message = "External namespace management and explicit agent namespace overrides must remain supported."
  }
}

run "operator_disabled" {
  command = plan
  variables {
    ravion_operator_enabled = false
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0
    error_message = "Disabling Operator must skip namespace bootstrap."
  }
}

run "invalid_namespace_rejected" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = ["Invalid_Namespace"]
  }
  expect_failures = [var.ravion_operator_deploy_namespaces]
}

run "operator_inline_upgrade_identity" {
  command = plan
  assert {
    condition = (
      helm_release.ravion_operator[0].repository == "oci://public.ecr.aws/a8z1i1r2" &&
      helm_release.ravion_operator[0].chart == "operator" &&
      helm_release.ravion_operator[0].version == "0.5.10" &&
      helm_release.ravion_operator[0].name == "ravion-operator" &&
      helm_release.ravion_operator[0].take_ownership == true &&
      !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0])), "nameOverride") &&
      !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0])), "fullnameOverride") &&
      yamldecode(helm_release.ravion_operator[0].values[0]).cluster.installationId == "opagt_test"
    )
    error_message = "The Operator chart must receive installation identity under the ravion-operator release name with no legacy name overrides, taking ownership of retained cluster-scoped objects."
  }
  assert {
    condition = (
      yamldecode(helm_release.ravion_operator[0].values[0]).controlPlane.endpoint == "wss://websockets.ravion.com/operator/v1/connect" &&
      yamldecode(helm_release.ravion_operator[0].values[0]).selfUpdate.enabled &&
      !yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.enabled &&
      !yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.enabled &&
      !yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.adaptive
    )
    error_message = "Inline mode must keep its update behavior without silently enabling executor Jobs or HA."
  }
}

run "operator_ha_full_management" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled  = true
    ravion_operator_chart_version           = "0.5.10"
    ravion_operator_coordinator_enabled     = true
    ravion_operator_full_management_enabled = true
    ravion_operator_deploy_namespaces       = []
  }
  assert {
    condition = (
      ravion_operator_credential.this[0].capabilities.self_update_allowed &&
      yamldecode(helm_release.ravion_operator[0].values[0]).selfUpdate.enabled &&
      yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.image == var.ravion_operator_execution_image &&
      yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.fullManagement &&
      !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs), "maxConcurrent") &&
      yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 2 &&
      !yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.adaptive &&
      yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes &&
      length(helm_release.ravion_operator_namespaces) == 0
    )
    error_message = "Full management must leave capacity to the control plane, wire two fixed Karpenter-placed coordinators, use the bundled image, and keep self-update enabled in enrollment and Helm."
  }
}

# Fixed coordinators never list nodes, so scoped observation no longer
# constrains HA.
run "scoped_observation_allows_ha" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled = true
    ravion_operator_execution_image        = "public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ravion_operator_chart_version          = "0.4.1-ci.test"
    ravion_operator_coordinator_enabled    = true
    ravion_operator_namespace_scope        = ["rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.enabled && yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 2 && yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes
    error_message = "HA coordinators must keep their fixed Karpenter-style placement under scoped observation."
  }
}

# A single eligible node runs one coordinator; under self-update it must drop
# the distinct-node placement so the rollout can surge and keep an observer.
run "single_replica_without_distinct_nodes" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled             = true
    ravion_operator_execution_image                    = "public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ravion_operator_chart_version                      = "0.4.1-ci.test"
    ravion_operator_self_update_enabled                = true
    ravion_operator_coordinator_enabled                = true
    ravion_operator_coordinator_replicas               = 1
    ravion_operator_coordinator_distinct_nodes_enabled = false
    ravion_operator_namespace_scope                    = ["rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.replicas == 1 && !yamldecode(helm_release.ravion_operator[0].values[0]).coordinator.requireDistinctNodes
    error_message = "A single coordinator without distinct nodes must plan for a single-node cluster."
  }
}

run "single_replica_on_distinct_nodes_needs_an_observer" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled = true
    ravion_operator_execution_image        = "public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ravion_operator_chart_version          = "0.4.1-ci.test"
    ravion_operator_self_update_enabled    = true
    ravion_operator_coordinator_enabled    = true
    ravion_operator_coordinator_replicas   = 1
  }
  expect_failures = [helm_release.ravion_operator]
}

run "jobs_use_bundled_image_and_capacity_default" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled = true
    ravion_operator_chart_version          = "0.4.1-ci.312e8f5638dc"
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.image == "" && !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs), "maxConcurrent")
    error_message = "Published charts supply the image digest, and the control plane decides capacity."
  }
}

run "jobs_require_explicit_chart_version" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled = true
    ravion_operator_chart_version          = null
  }
  expect_failures = [helm_release.ravion_operator]
}

run "ha_requires_jobs" {
  command = plan
  variables {
    ravion_operator_coordinator_enabled = true
  }
  expect_failures = [helm_release.ravion_operator]
}

run "full_management_requires_jobs" {
  command = plan
  variables {
    ravion_operator_full_management_enabled = true
    ravion_operator_deploy_namespaces       = []
  }
  expect_failures = [helm_release.ravion_operator]
}

run "full_management_rejects_namespace_scope" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled  = true
    ravion_operator_execution_image         = "public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ravion_operator_full_management_enabled = true
  }
  expect_failures = [helm_release.ravion_operator]
}

run "full_management_allows_parallel_deploys" {
  command = plan
  variables {
    ravion_operator_execution_jobs_enabled   = true
    ravion_operator_execution_image          = "public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ravion_operator_full_management_enabled  = true
    ravion_operator_deploy_namespaces        = []
    ravion_operator_execution_max_concurrent = 2
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.maxConcurrent == 2
    error_message = "Full management deploys releases in parallel up to the configured capacity."
  }
}
