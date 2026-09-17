# The ECS cluster module names its load balancers <cluster>-pub / <cluster>-priv,
# and a cluster migrating from ECS is naturally named like the ECS one, so the
# add-ons default to <cluster>-eks-* and never collide. load_balancer_name_prefix
# still moves the names outright without touching anything else.

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
  eso_enabled                  = false
  logs_providers               = []
  metrics_providers            = []
  ravion_operator_enabled      = false
}

run "names_default_to_the_cluster_name_with_an_eks_suffix" {
  command = plan

  assert {
    condition     = module.public_alb[0].security_group_name == "test-cluster-eks-pub-alb" && module.public_alb[0].load_balancer_name == "test-cluster-eks-pub"
    error_message = "Without a prefix the public ALB and its security group must be named <cluster>-eks-pub, clear of the ECS module's <cluster>-pub."
  }
  assert {
    condition     = module.private_alb[0].load_balancer_name == "test-cluster-eks-priv"
    error_message = "Without a prefix the private ALB must be named <cluster>-eks-priv."
  }
  assert {
    condition     = module.public_nlb[0].load_balancer_name == "test-cluster-eks-pub-nlb" && module.private_nlb[0].load_balancer_name == "test-cluster-eks-priv-nlb"
    error_message = "Without a prefix the NLBs must be named <cluster>-eks-pub-nlb and <cluster>-eks-priv-nlb."
  }
}

run "prefix_moves_every_load_balancer_and_security_group" {
  command = plan
  variables {
    load_balancer_name_prefix = "shared-lb"
  }

  assert {
    condition     = module.public_alb[0].load_balancer_name == "shared-lb-pub" && module.public_alb[0].security_group_name == "shared-lb-pub-alb"
    error_message = "The prefix must rename the public ALB and its security group together."
  }
  assert {
    condition     = module.private_alb[0].load_balancer_name == "shared-lb-priv" && module.private_alb[0].security_group_name == "shared-lb-priv-alb"
    error_message = "The prefix must rename the private ALB and its security group together."
  }
  assert {
    condition     = module.public_nlb[0].load_balancer_name == "shared-lb-pub-nlb" && module.private_nlb[0].load_balancer_name == "shared-lb-priv-nlb"
    error_message = "The prefix must rename both NLBs."
  }
}

run "prefix_too_long_for_the_nlb_name_is_rejected" {
  command = plan
  variables {
    load_balancer_name_prefix = "a-prefix-that-is-24-chars"
  }
  expect_failures = [var.load_balancer_name_prefix]
}
