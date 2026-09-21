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

run "runtime_policy_is_left_to_the_control_plane" {
  command = plan
  variables {
    ravion_operator_full_management_enabled = true
  }
  assert {
    condition     = length(setintersection(keys(yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs), ["maxConcurrent", "settingsSource", "resourcesSource", "resources"])) == 0
    error_message = "With nothing set, the module leaves capacity and executor resources to runtime policy."
  }
}

run "scoped_execution_is_left_to_the_control_plane" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = ["rvn-app"]
  }
  assert {
    condition     = !contains(keys(yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs), "maxConcurrent")
    error_message = "Scoped installs leave capacity to the control plane too."
  }
}

run "a_set_value_pins_capacity_locally" {
  command = plan
  variables {
    ravion_operator_full_management_enabled  = true
    ravion_operator_execution_max_concurrent = 2
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.maxConcurrent == 2
    error_message = "An explicit capacity reaches the chart."
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator[0].values[0]).executionJobs.settingsSource == "local"
    error_message = "An explicit value pins capacity against control-plane changes."
  }
}
