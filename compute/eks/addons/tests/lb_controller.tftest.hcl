# Plan-only coverage for CRD adoption and chart-version wiring. No live APIs.
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
mock_provider "helm" {
  mock_data "helm_template" {
    defaults = { crds = ["apiVersion: apiextensions.k8s.io/v1\nkind: CustomResourceDefinition\nmetadata:\n  name: targetgroupbindings.elbv2.k8s.aws\n"] }
  }
}
mock_provider "ravion" {}

variables {
  cluster_name                         = "test-cluster"
  region                               = "us-east-2"
  karpenter_enabled                    = false
  eso_enabled                          = false
  ravion_operator_enabled              = false
  logs_providers                       = []
  metrics_providers                    = []
  aws_load_balancer_controller_enabled = true
}

run "adopt_existing_crds_before_upgrading_the_controller" {
  command = plan

  assert {
    condition     = helm_release.lb_controller_crds[0].take_ownership && helm_release.lb_controller_crds[0].upgrade_install
    error_message = "The CRD release must adopt CRDs from an earlier controller install or a retained release."
  }
  assert {
    condition     = helm_release.lb_controller[0].skip_crds
    error_message = "The controller must leave CRD management to the dedicated release."
  }
  assert {
    condition     = data.helm_template.lb_controller[0].version == helm_release.lb_controller[0].version && data.helm_template.lb_controller[0].chart == helm_release.lb_controller[0].chart && data.helm_template.lb_controller[0].repository == helm_release.lb_controller[0].repository
    error_message = "CRDs must come from the exact same upstream chart and version as the controller."
  }
  assert {
    condition     = data.helm_template.lb_controller[0].include_crds
    error_message = "The upstream chart render must explicitly include CRDs."
  }
  assert {
    condition     = tolist(yamldecode(helm_release.lb_controller_crds[0].values[0]).crds) == data.helm_template.lb_controller[0].crds
    error_message = "The CRD wrapper must receive the upstream CRD files, not a fixed bundled version."
  }
  assert {
    condition     = helm_release.lb_controller_crds[0].version == yamldecode(file("charts/aws-load-balancer-controller-crds/Chart.yaml")).version
    error_message = "The CRD release must pin the wrapper chart version so plans pick up wrapper version bumps."
  }
}

run "custom_version_pin_also_selects_its_crds" {
  command = plan
  variables {
    aws_load_balancer_controller_chart_version = "1.14.0"
  }
  assert {
    condition     = data.helm_template.lb_controller[0].version == "1.14.0" && helm_release.lb_controller[0].version == "1.14.0"
    error_message = "An existing controller pin must also select its matching CRDs."
  }
}

run "disabled_controller_does_not_fetch_or_install_crds" {
  command = plan
  variables {
    aws_load_balancer_controller_enabled = false
  }
  assert {
    condition     = length(data.helm_template.lb_controller) == 0 && length(helm_release.lb_controller_crds) == 0 && length(helm_release.lb_controller) == 0
    error_message = "When no controller is needed, no upstream chart should be fetched or installed."
  }
}
