################################################################################
# External Secrets store scoping
#
# The ClusterSecretStores are reachable from every namespace unless they carry
# a namespace condition. By default that condition is the set of namespaces
# Ravion Operator manages; an explicit list replaces it.
################################################################################

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
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = true
  logs_providers    = []
  metrics_providers = []
}

run "stores_default_to_the_operator_workload_namespaces" {
  command = plan
  variables {
    ravion_operator_enabled           = true
    ravion_operator_deploy_enabled    = true
    ravion_operator_deploy_namespaces = ["rvn-app", "rvn-jobs", "rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.external_secrets_stores[0].values[0]).allowedNamespaces == ["rvn-app", "rvn-jobs"]
    error_message = "Without an explicit list the stores must admit exactly the namespaces Ravion Operator deploys into, deduplicated and sorted."
  }
}

run "explicit_namespaces_replace_the_default" {
  command = plan
  variables {
    ravion_operator_enabled           = true
    ravion_operator_deploy_enabled    = true
    ravion_operator_deploy_namespaces = ["rvn-app"]
    eso_allowed_namespaces            = ["platform", "data"]
  }
  assert {
    condition     = yamldecode(helm_release.external_secrets_stores[0].values[0]).allowedNamespaces == ["data", "platform"]
    error_message = "An explicit allow-list must replace the operator-derived default rather than merge with it."
  }
}

run "stores_stay_open_when_nothing_scopes_them" {
  command = plan
  variables {
    ravion_operator_enabled = false
  }
  assert {
    condition     = length(yamldecode(helm_release.external_secrets_stores[0].values[0]).allowedNamespaces) == 0
    error_message = "With no operator namespaces and no explicit list the chart must receive an empty list, which renders no condition."
  }
}
