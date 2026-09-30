################################################################################
# Loki query endpoint inside the VPC
#
# An internal NLB in front of Loki for clients outside the cluster, admitting
# only the Loki client security group. Run from the module root: `tofu test`.
################################################################################

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_region" {
    defaults = {
      id     = "us-east-2"
      name   = "us-east-2"
      region = "us-east-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.gr7.us-east-2.eks.amazonaws.com"
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
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/test-cluster-loki/abc"
      dns_name = "test-cluster-loki-abc.elb.us-east-2.amazonaws.com"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/test-cluster-loki/def"
    }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      id  = "ws-11111111-2222-3333-4444-555555555555"
      arn = "arn:aws:aps:us-east-2:123456789012:workspace/ws-11111111-2222-3333-4444-555555555555"
    }
  }
}

mock_provider "helm" {}

# Ravion Operator's credential is minted by Ravion's own provider, which refuses to
# configure without a runner JWT.
mock_provider "ravion" {}

# Both signals start empty so every run opts into exactly the providers it is
# about. The defaults ([loki] and [amp]) have their own coverage in
# observability.tftest.hcl.
variables {
  cluster_name      = "test-cluster"
  region            = "us-east-2"
  karpenter_enabled = false
  eso_enabled       = false
  logs_providers    = []
  metrics_providers = []
}

################################################################################
# Logs off — the default. No bucket, no Loki, no Alloy, no IAM.
################################################################################


run "no_loki_endpoint_by_default" {
  command = plan

  variables {
    logs_providers = ["loki"]
  }

  assert {
    condition     = length(module.loki_nlb) == 0 && length(helm_release.loki_vpc_endpoint) == 0 && length(module.loki_client_security_group) == 0
    error_message = "Loki must stay in-cluster unless its VPC endpoint is asked for"
  }

  assert {
    condition     = output.loki_vpc_query_url == null && output.loki_client_security_group_id == null
    error_message = "The Loki endpoint outputs must be null while the endpoint is off"
  }
}

run "loki_endpoint_admits_only_its_client_security_group" {
  command = apply

  variables {
    logs_providers            = ["loki"]
    loki_vpc_endpoint_enabled = true
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    node_subnet_ids           = ["subnet-11111111", "subnet-22222222"]
  }

  assert {
    condition     = length(module.loki_nlb) == 1 && length(module.loki_nlb[0].security_group_id) > 0
    error_message = "An internal load balancer must front Loki"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.loki_nlb_from_clients[0].referenced_security_group_id == module.loki_client_security_group[0].security_group_id && aws_vpc_security_group_ingress_rule.loki_nlb_from_clients[0].from_port == 3100
    error_message = "The load balancer must admit the Loki client security group on 3100 and nothing else"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cluster_from_loki_nlb[0].security_group_id == "sg-0aaaaaaaaaaaaaaaa" && aws_vpc_security_group_ingress_rule.cluster_from_loki_nlb[0].from_port == 3100 && aws_vpc_security_group_ingress_rule.cluster_from_loki_nlb[0].to_port == 3100
    error_message = "The cluster security group must admit the load balancer on Loki's port only"
  }

  assert {
    condition     = aws_lb_target_group.loki[0].target_type == "ip" && aws_lb_target_group.loki[0].port == 3100 && aws_lb_listener.loki[0].port == 3100
    error_message = "The target group must register Loki pod IPs on 3100 behind a listener on 3100"
  }

  assert {
    condition     = yamldecode(helm_release.loki_vpc_endpoint[0].values[0]).serviceName == "ravion-loki" && yamldecode(helm_release.loki_vpc_endpoint[0].values[0]).targetGroupArn == aws_lb_target_group.loki[0].arn
    error_message = "The TargetGroupBinding must bind Loki's Service to the target group"
  }

  assert {
    condition     = output.loki_vpc_query_url == "http://test-cluster-loki-abc.elb.us-east-2.amazonaws.com:3100" && output.loki_client_security_group_id == module.loki_client_security_group[0].security_group_id
    error_message = "The outputs must give the query URL and the client security group"
  }

  assert {
    condition     = length(helm_release.lb_controller) == 1
    error_message = "The load balancer controller must be installed to reconcile the TargetGroupBinding"
  }
}

run "loki_endpoint_needs_loki" {
  command = plan

  variables {
    loki_vpc_endpoint_enabled = true
  }

  assert {
    condition     = length(module.loki_nlb) == 0 && output.loki_vpc_query_url == null
    error_message = "There is no Loki to front while Loki is not a logs destination"
  }
}
