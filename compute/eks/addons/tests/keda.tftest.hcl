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

variables {
  traces_destinations                  = []
  ebs_csi_driver_enabled               = false
  cluster_name                         = "test-cluster"
  region                               = "us-east-2"
  cluster_security_group_id            = "sg-12345678"
  node_subnet_ids                      = ["subnet-0a", "subnet-0b"]
  karpenter_enabled                    = false
  eso_enabled                          = false
  ravion_operator_enabled              = false
  logs_providers                       = []
  metrics_providers                    = []
  aws_load_balancer_controller_enabled = false
}

run "keda_is_disabled_by_default" {
  command = plan

  assert {
    condition     = length(helm_release.keda) == 0
    error_message = "KEDA must not install unless explicitly enabled."
  }
  assert {
    condition     = output.keda_enabled == false && output.keda_namespace == null && output.keda_chart_version == null
    error_message = "Disabled KEDA outputs must reflect that no release is installed."
  }
}

run "keda_installs_the_pinned_chart_and_on_demand_components" {
  command = plan

  variables {
    keda_enabled       = true
    keda_namespace     = "keda-test"
    keda_chart_version = "2.20.2"
  }

  assert {
    condition     = helm_release.keda[0].name == "keda" && helm_release.keda[0].namespace == "keda-test" && helm_release.keda[0].repository == "https://kedacore.github.io/charts" && helm_release.keda[0].chart == "keda" && helm_release.keda[0].version == "2.20.2"
    error_message = "KEDA must use the requested namespace and pinned official chart."
  }
  assert {
    condition     = helm_release.keda[0].create_namespace && helm_release.keda[0].wait && yamldecode(helm_release.keda[0].values[0]).crds.install
    error_message = "KEDA must create its namespace, wait for readiness, and install CRDs."
  }
  assert {
    condition     = length(yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms) == 2 && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key == "eks.amazonaws.com/capacityType" && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values == ["ON_DEMAND"] && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].key == "karpenter.sh/capacity-type" && yamldecode(helm_release.keda[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].values == ["on-demand"]
    error_message = "KEDA controller components must stay on On-Demand managed-group or Karpenter capacity."
  }
  assert {
    condition     = output.keda_enabled && output.keda_namespace == "keda-test" && output.keda_chart_version == "2.20.2"
    error_message = "Enabled KEDA outputs must report the installed release."
  }
}

run "advanced_helm_values_override_keda_defaults" {
  command = plan

  variables {
    keda_enabled     = true
    keda_helm_values = ["crds:\n  install: false"]
  }

  assert {
    condition     = length(helm_release.keda[0].values) == 3 && yamldecode(helm_release.keda[0].values[2]).crds.install == false
    error_message = "Advanced KEDA values must be appended after defaults and take precedence."
  }
}

run "disabling_keda_removes_the_release" {
  command = plan

  variables {
    keda_enabled = false
  }

  assert {
    condition     = length(helm_release.keda) == 0 && output.keda_enabled == false
    error_message = "Disabling KEDA must remove the release and clear the enabled output."
  }
}
