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
  cluster_name                           = "test-cluster"
  region                                 = "us-east-2"
  karpenter_enabled                      = false
  eso_enabled                            = false
  logs_providers                         = []
  metrics_providers                      = []
  ravion_operator_enabled                = true
  ravion_operator_deploy_enabled         = true
  ravion_operator_chart_version          = "0.6.0"
  ravion_operator_execution_jobs_enabled = true
}

run "full_management_runs_six_releases_at_once" {
  command = plan
  variables {
    ravion_operator_full_management_enabled = true
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.maxConcurrent == 6
    error_message = "Executor capacity defaults to six, under full management too."
  }
  assert {
    condition     = !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs), "laneScope")
    error_message = "The lane scope is left to the chart's default unless overridden."
  }
}

run "scoped_execution_runs_six_releases_at_once" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = ["rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.maxConcurrent == 6
    error_message = "Executor capacity defaults to six."
  }
}

run "overrides_reach_the_chart" {
  command = plan
  variables {
    ravion_operator_full_management_enabled  = true
    ravion_operator_execution_max_concurrent = 2
    ravion_operator_execution_lane_scope     = "namespace"
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.maxConcurrent == 2
    error_message = "An explicit capacity reaches the chart."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.laneScope == "namespace"
    error_message = "An explicit lane scope reaches the chart."
  }
}

run "unknown_lane_scope_is_refused" {
  command = plan
  variables {
    ravion_operator_execution_lane_scope = "cluster"
  }
  expect_failures = [var.ravion_operator_execution_lane_scope]
}
