# The default NodePool/EC2NodeClass release is the only place Karpenter's node
# hardening is rendered, so it needs a run with Karpenter actually enabled:
# 0.9.0 shipped a coalesce() that failed every install without a customer KMS key
# because no test turned Karpenter on.

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
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:mock", url = "https://sqs.us-east-2.amazonaws.com/123456789012/mock" }
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
  cluster_name              = "test-cluster"
  region                    = "us-east-2"
  cluster_security_group_id = "sg-12345678"
  node_subnet_ids           = ["subnet-0a", "subnet-0b"]
  karpenter_enabled         = true
  eso_enabled               = false
  logs_providers            = []
  metrics_providers         = []
  ravion_operator_enabled   = false
}

run "default_node_pool_renders_hardened_without_a_customer_key" {
  command = plan

  assert {
    condition     = length(helm_release.karpenter_default_node_pool) == 1
    error_message = "Karpenter on must render the default NodePool release."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).ec2NodeClass.rootVolume.kmsKeyId == ""
    error_message = "With no customer key the chart must receive an empty kmsKeyId so the AWS-managed key applies."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).ec2NodeClass.metadataHopLimit == 1
    error_message = "Karpenter nodes must launch with an IMDS hop limit of 1."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).ec2NodeClass.rootVolume == { deviceName = "/dev/xvda", size = "20Gi", type = "gp3", kmsKeyId = "" }
    error_message = "The default root volume must be a 20Gi gp3 on /dev/xvda with the AWS-managed key."
  }
}

run "customer_managed_key_reaches_the_node_class" {
  command = plan
  variables {
    karpenter_default_node_pool = {
      ebs_kms_key_arn  = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
      root_volume_size = "50Gi"
    }
  }

  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).ec2NodeClass.rootVolume.kmsKeyId == "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A customer-managed key must be passed through to the EC2NodeClass."
  }
  assert {
    condition     = yamldecode(helm_release.karpenter_default_node_pool[0].values[0]).ec2NodeClass.rootVolume.size == "50Gi"
    error_message = "The root volume size override must reach the EC2NodeClass."
  }
}

run "rejects_a_non_kms_key_arn" {
  command = plan
  variables {
    karpenter_default_node_pool = {
      ebs_kms_key_arn = "arn:aws:iam::123456789012:role/not-a-key"
    }
  }
  expect_failures = [var.karpenter_default_node_pool]
}
