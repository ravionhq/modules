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
  cluster_name                            = "test-cluster"
  region                                  = "us-east-2"
  karpenter_enabled                       = false
  eso_enabled                             = false
  logs_providers                          = []
  metrics_providers                       = []
  ravion_operator_enabled                 = true
  ravion_operator_deploy_enabled          = true
  ravion_operator_execution_jobs_enabled  = true
  ravion_operator_full_management_enabled = true
}

run "warm_capacity_is_disabled_by_default" {
  command = plan

  assert {
    condition     = length(helm_release.ravion_operator_warm_capacity) == 0
    error_message = "Warm-capacity reservation must be opt-in."
  }
}

run "warm_capacity_settings_reach_the_chart" {
  command = plan
  variables {
    ravion_operator_warm_capacity = {
      enabled  = true
      replicas = 9
      requests = {
        cpu               = "250m"
        memory            = "512Mi"
        ephemeral_storage = "2Gi"
      }
      placement = {
        node_selector = { "karpenter.sh/nodepool" = "default" }
        tolerations = [{
          key      = "dedicated"
          operator = "Equal"
          value    = "apps"
          effect   = "NoSchedule"
        }]
        topology_spread_enabled            = true
        topology_spread_key                = "kubernetes.io/hostname"
        topology_spread_when_unsatisfiable = "DoNotSchedule"
      }
    }
  }

  assert {
    condition = (
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).replicas == 9 &&
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).resources.requests.cpu == "250m" &&
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).resources.requests.memory == "512Mi" &&
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).resources.requests["ephemeral-storage"] == "2Gi" &&
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).nodeSelector["karpenter.sh/nodepool"] == "default" &&
      yamldecode(helm_release.ravion_operator_warm_capacity[0].values[0]).topologySpread.whenUnsatisfiable == "DoNotSchedule"
    )
    error_message = "Warm-capacity count, requests and placement must reach the local chart."
  }
}
