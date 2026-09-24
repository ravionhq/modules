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
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.66.0-eksbuild.1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-cluster-ebs-csi" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      version               = "1.36"
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
  ebs_csi_driver_enabled  = true
}

run "installs_gp3_and_volume_expansion_by_default" {
  command = plan
  assert {
    condition     = length(helm_release.ebs_storage) == 1 && helm_release.ebs_storage[0].namespace == "kube-system"
    error_message = "The EBS storage chart must install with the EBS CSI driver."
  }
  assert {
    condition     = yamldecode(helm_release.ebs_storage[0].values[0]).storageClass.enabled && yamldecode(helm_release.ebs_storage[0].values[0]).volumeExpansion.enabled
    error_message = "The gp3 StorageClass and StatefulSet volume expansion must both be on by default."
  }
  assert {
    condition     = yamldecode(helm_release.ebs_storage[0].values[0]).busyboxImage == { repository = "public.ecr.aws/docker/library/busybox", tag = "1.37.0-musl" }
    error_message = "The pinned busybox image must reach the chart split into repository and tag."
  }
  assert {
    condition     = output.default_storage_class_name == "gp3" && output.statefulset_volume_expansion_enabled
    error_message = "Outputs must report the gp3 class and volume expansion."
  }
}

run "nothing_without_ebs_csi" {
  command = plan
  variables {
    ebs_csi_driver_enabled = false
  }
  assert {
    condition     = length(helm_release.ebs_storage) == 0 && output.default_storage_class_name == null
    error_message = "Without the EBS CSI driver there is no provisioner for the class, so nothing is installed."
  }
}

run "storage_class_only_before_kubernetes_1_36" {
  command = plan
  override_data {
    target = data.aws_eks_cluster.this
    values = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      version               = "1.35"
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
  assert {
    condition     = yamldecode(helm_release.ebs_storage[0].values[0]).storageClass.enabled && !yamldecode(helm_release.ebs_storage[0].values[0]).volumeExpansion.enabled
    error_message = "MutatingAdmissionPolicy is GA only from 1.36, so older clusters get the StorageClass alone."
  }
  expect_failures = [check.statefulset_volume_expansion_supported]
}

run "both_features_can_be_turned_off" {
  command = plan
  variables {
    ebs_default_storage_class_enabled    = false
    statefulset_volume_expansion_enabled = false
  }
  assert {
    condition     = length(helm_release.ebs_storage) == 0
    error_message = "With both features off the chart must not be installed."
  }
}
