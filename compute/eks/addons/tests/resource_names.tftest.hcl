# Every resource the add-ons create is named off one slug that defaults to the
# cluster name: <cluster>-pub / <cluster>-priv is exactly what the ECS cluster
# module names its own, so a same-named ECS cluster in the account makes the
# add-ons apply fail on a duplicate security group. `name` moves every name at
# once while cluster_name keeps addressing the cluster.

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
  # Pod Identity associations validate the role ARN they are handed.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  # Listeners validate the load balancer ARN they are handed.
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/mock/0123456789abcdef" }
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
  cluster_name                 = "test-cluster"
  region                       = "us-east-2"
  cluster_security_group_id    = "sg-12345678"
  public_subnet_ids            = ["subnet-0a", "subnet-0b"]
  node_subnet_ids              = ["subnet-1a", "subnet-1b"]
  public_alb_creation_enabled  = true
  private_alb_creation_enabled = true
  public_nlb_creation_enabled  = true
  private_nlb_creation_enabled = true
  karpenter_enabled            = false
  eso_enabled                  = true
  eso_allowed_namespaces       = ["apps"]
  logs_providers               = []
  metrics_providers            = []
  ravion_operator_enabled      = false
}

run "names_default_to_the_cluster_name" {
  command = plan

  assert {
    condition     = module.public_alb[0].security_group_name == "test-cluster-pub-alb" && module.public_alb[0].load_balancer_name == "test-cluster-pub"
    error_message = "Without a name the public ALB and its security group must keep the <cluster>-pub names."
  }
  assert {
    condition     = module.private_alb[0].load_balancer_name == "test-cluster-priv"
    error_message = "Without a name the private ALB must keep the <cluster>-priv name."
  }
  assert {
    condition     = module.public_nlb[0].load_balancer_name == "test-cluster-pub-nlb" && module.private_nlb[0].load_balancer_name == "test-cluster-priv-nlb"
    error_message = "Without a name the NLBs must keep the <cluster>-pub-nlb and <cluster>-priv-nlb names."
  }
  assert {
    condition     = module.external_secrets_role[0].role_name == "test-cluster-external-secrets"
    error_message = "Without a name the Pod Identity roles must keep the <cluster>-* names."
  }
}

run "name_moves_every_load_balancer_security_group_and_role" {
  command = plan
  variables {
    name = "test-cluster-eks"
  }

  assert {
    condition     = module.public_alb[0].load_balancer_name == "test-cluster-eks-pub" && module.public_alb[0].security_group_name == "test-cluster-eks-pub-alb"
    error_message = "The name must rename the public ALB and its security group together."
  }
  assert {
    condition     = module.private_alb[0].load_balancer_name == "test-cluster-eks-priv" && module.private_alb[0].security_group_name == "test-cluster-eks-priv-alb"
    error_message = "The name must rename the private ALB and its security group together."
  }
  assert {
    condition     = module.public_nlb[0].load_balancer_name == "test-cluster-eks-pub-nlb" && module.private_nlb[0].load_balancer_name == "test-cluster-eks-priv-nlb"
    error_message = "The name must rename both NLBs."
  }
  assert {
    condition     = module.external_secrets_role[0].role_name == "test-cluster-eks-external-secrets"
    error_message = "The name must rename the Pod Identity roles too."
  }
  assert {
    condition     = aws_eks_pod_identity_association.external_secrets[0].cluster_name == "test-cluster"
    error_message = "The name must not change how the cluster is addressed."
  }
}

run "name_too_long_for_the_nlb_name_is_rejected" {
  command = plan
  variables {
    name = "a-prefix-that-is-24-chars"
  }
  expect_failures = [var.name]
}
