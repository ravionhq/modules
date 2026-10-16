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

run "cert_manager_is_disabled_by_default" {
  command = plan

  assert {
    condition     = length(helm_release.cert_manager) == 0
    error_message = "cert-manager must not install unless explicitly enabled."
  }
  assert {
    condition     = output.cert_manager_enabled == false && output.cert_manager_namespace == null && output.cert_manager_chart_version == null
    error_message = "Disabled cert-manager outputs must reflect that no release is installed."
  }
}

run "cert_manager_installs_the_pinned_chart_with_retained_crds" {
  command = plan

  variables {
    cert_manager_enabled       = true
    cert_manager_namespace     = "cert-manager-test"
    cert_manager_chart_version = "v1.21.2"
  }

  assert {
    condition     = helm_release.cert_manager[0].name == "cert-manager" && helm_release.cert_manager[0].namespace == "cert-manager-test" && helm_release.cert_manager[0].repository == "https://charts.jetstack.io" && helm_release.cert_manager[0].chart == "cert-manager" && helm_release.cert_manager[0].version == "v1.21.2"
    error_message = "cert-manager must use the requested namespace and pinned official chart."
  }
  assert {
    condition     = helm_release.cert_manager[0].create_namespace && helm_release.cert_manager[0].wait && yamldecode(helm_release.cert_manager[0].values[0]).crds.enabled && yamldecode(helm_release.cert_manager[0].values[0]).crds.keep
    error_message = "cert-manager must create its namespace, wait for readiness, and install CRDs that survive an uninstall."
  }
  assert {
    condition = alltrue([
      for affinity in [
        yamldecode(helm_release.cert_manager[0].values[0]).affinity,
        yamldecode(helm_release.cert_manager[0].values[0]).webhook.affinity,
        yamldecode(helm_release.cert_manager[0].values[0]).cainjector.affinity,
        yamldecode(helm_release.cert_manager[0].values[0]).startupapicheck.affinity,
      ] :
      length(affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms) == 2
      && affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key == "eks.amazonaws.com/capacityType"
      && affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values == ["ON_DEMAND"]
      && affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].key == "karpenter.sh/capacity-type"
      && affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[1].matchExpressions[0].values == ["on-demand"]
    ])
    error_message = "Every cert-manager component must stay on On-Demand managed-group or Karpenter capacity."
  }
  assert {
    condition = alltrue([
      for tolerations in [
        yamldecode(helm_release.cert_manager[0].values[1]).tolerations,
        yamldecode(helm_release.cert_manager[0].values[1]).webhook.tolerations,
        yamldecode(helm_release.cert_manager[0].values[1]).cainjector.tolerations,
        yamldecode(helm_release.cert_manager[0].values[1]).startupapicheck.tolerations,
      ] : tolerations == [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    ])
    error_message = "Every cert-manager component must tolerate a CriticalAddonsOnly system group when add-on placement is on."
  }
  assert {
    condition     = output.cert_manager_enabled && output.cert_manager_namespace == "cert-manager-test" && output.cert_manager_chart_version == "v1.21.2"
    error_message = "Enabled cert-manager outputs must report the installed release."
  }
}

run "placement_opt_out_drops_cert_manager_tolerations" {
  command = plan

  variables {
    cert_manager_enabled    = true
    addon_placement_enabled = false
    # Resilience has its own document; leave it out to see placement alone.
    addon_resilience_enabled = false
  }

  assert {
    condition     = length(helm_release.cert_manager[0].values) == 1 && yamldecode(helm_release.cert_manager[0].values[0]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values == ["ON_DEMAND"]
    error_message = "Placement opt-out must drop the tolerations document but keep cert-manager on On-Demand capacity."
  }
}

run "advanced_helm_values_override_cert_manager_defaults" {
  command = plan

  variables {
    cert_manager_enabled     = true
    cert_manager_helm_values = ["webhook:\n  replicaCount: 3"]
  }

  assert {
    condition     = length(helm_release.cert_manager[0].values) == 4 && yamldecode(helm_release.cert_manager[0].values[3]).webhook.replicaCount == 3
    error_message = "Advanced cert-manager values must be appended after defaults and take precedence."
  }
}

run "cert_manager_rejects_an_unpinned_chart_version" {
  command = plan

  variables {
    cert_manager_enabled       = true
    cert_manager_chart_version = "v1.21"
  }

  expect_failures = [var.cert_manager_chart_version]
}
