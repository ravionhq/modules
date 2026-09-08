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

variables {
  cluster_name        = "test-cluster"
  region              = "us-east-2"
  karpenter_enabled   = false
  eso_enabled         = false
  logs_providers      = []
  metrics_providers   = []
  workload_namespaces = ["rvn-app", "rvn-app"]
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
    condition     = helm_release.ravion_operator_namespaces[0].name == "ravion-operator-namespaces"
    error_message = "The existing namespace release must keep its identity."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).helmInventoryNamespaces == ["rvn-app"]
    error_message = "Deployment namespaces must receive Helm storage read permissions by default."
  }
}

run "bootstrap_observation_and_deployment_namespaces" {
  command = plan
  variables {
    observed_namespaces = ["observed", "rvn-app", "observed"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed", "rvn-app"]
    error_message = "Both observation and deployment RBAC require existing namespaces."
  }
  assert {
    condition     = join(",", output.ravion_access_helm_inventory_namespaces) == "observed,rvn-app" && yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).helmInventoryNamespaces == ["observed", "rvn-app"]
    error_message = "Helm inventory reads must use the deduplicated union of deployment and observation scopes."
  }
}

run "single_namespace" {
  command = plan
  variables {
    workload_namespaces = []
    observed_namespaces = ["observed"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed"]
    error_message = "Bootstrap must follow the chart's observation-scope fallback."
  }
}

run "no_bootstrap_for_empty_namespaces" {
  command = plan
  variables {
    workload_namespaces = []
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0
    error_message = "Unused deployment namespaces must not be created."
  }
  assert {
    condition     = length(output.ravion_access_helm_inventory_namespaces) == 0
    error_message = "Empty scope must never become a cluster-wide Secret grant."
  }
}

run "externally_provisioned_namespaces" {
  command = plan
  variables {
    workload_namespaces_creation_enabled = false
  }
  assert {
    condition     = length(yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces) == 0 && yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).helmInventoryNamespaces == ["rvn-app"]
    error_message = "External namespace management must skip creation while retaining namespace-scoped Helm read grants."
  }
}

run "bootstrap_independent_of_observability" {
  command = plan
  variables {
    observability_namespace = "custom-observability"
  }
  assert {
    condition     = helm_release.ravion_operator_namespaces[0].namespace == "kube-system"
    error_message = "Bootstrap identity must be independent of observability."
  }
}

run "invalid_namespace_rejected" {
  command = plan
  variables {
    workload_namespaces = ["Invalid_Namespace"]
  }
  expect_failures = [var.workload_namespaces]
}

run "invalid_observed_namespace_rejected" {
  command = plan
  variables {
    observed_namespaces = ["*"]
  }
  expect_failures = [var.observed_namespaces]
}

run "scope_removal_retracts_read_grants" {
  command = plan
  variables {
    workload_namespaces = ["remaining"]
    observed_namespaces = []
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).helmInventoryNamespaces == ["remaining"]
    error_message = "Removed namespaces must not retain generated Secret read Roles. Namespace keep applies only to Namespace objects."
  }
}
