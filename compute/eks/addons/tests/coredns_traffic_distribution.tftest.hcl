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

variables {
  cluster_name            = "test-cluster"
  region                  = "us-east-2"
  karpenter_enabled       = false
  eso_enabled             = false
  logs_providers          = []
  metrics_providers       = []
  ravion_operator_enabled = false
}

run "patches_kube_dns_by_default" {
  command = plan
  assert {
    condition     = length(helm_release.coredns_traffic_distribution) == 1 && helm_release.coredns_traffic_distribution[0].namespace == "kube-system"
    error_message = "Zone-local DNS must be on by default and live next to kube-dns."
  }
  assert {
    condition     = yamldecode(helm_release.coredns_traffic_distribution[0].values[0]).trafficDistribution == "PreferClose"
    error_message = "The patch must prefer same-zone endpoints."
  }
  assert {
    condition     = yamldecode(helm_release.coredns_traffic_distribution[0].values[0]).image == { repository = "registry.k8s.io/kubectl", tag = "v1.33.12" }
    error_message = "The pinned kubectl image must reach the chart split into repository and tag."
  }
}

run "kubectl_image_override" {
  command = plan
  variables {
    kubectl_image = "123456789012.dkr.ecr.us-east-2.amazonaws.com/mirror/kubectl:v1.34.10"
  }
  assert {
    condition     = yamldecode(helm_release.coredns_traffic_distribution[0].values[0]).image == { repository = "123456789012.dkr.ecr.us-east-2.amazonaws.com/mirror/kubectl", tag = "v1.34.10" }
    error_message = "A registry with a port-free host and a path must split on the last colon."
  }
}

run "disabled" {
  command = plan
  variables {
    topology_aware_routing_enabled = false
  }
  assert {
    condition     = length(helm_release.coredns_traffic_distribution) == 0
    error_message = "Disabling zone-local DNS must remove the patch release so its pre-delete hook clears the field."
  }
}

run "invalid_kubectl_image_rejected" {
  command = plan
  variables {
    kubectl_image = "registry.k8s.io/kubectl"
  }
  expect_failures = [var.kubectl_image]
}
