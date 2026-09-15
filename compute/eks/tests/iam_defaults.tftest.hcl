mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-12345678" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/MOCK" }] }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/MOCK" }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{
        sha1_fingerprint     = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        cert_pem             = "mock-certificate"
        is_ca                = true
        issuer               = "CN=mock"
        subject              = "CN=mock"
        max_path_length      = -1
        not_after            = "2030-01-01T00:00:00Z"
        not_before           = "2020-01-01T00:00:00Z"
        public_key_algorithm = "RSA"
        signature_algorithm  = "SHA256-RSA"
        serial_number        = "1"
        version              = 3
      }]
    }
  }
}

run "cluster_defaults_need_no_irsa_or_vpc_controller" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                       = "test-cluster"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 0 && length(data.tls_certificate.oidc) == 0 && output.oidc_provider_arn == null
    error_message = "Pod Identity defaults must omit both IAM OIDC creation and the external TLS lookup."
  }
  assert {
    condition     = module.cluster_role.managed_policy_arns == tolist(["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"])
    error_message = "The ordinary Linux cluster role must keep EKS permissions without VPC controller permissions."
  }
  assert {
    condition     = length(aws_eks_addon.pod_identity_agent) == 1 && length(aws_eks_pod_identity_association.lb_controller) == 1
    error_message = "Removing IRSA defaults must preserve the existing Pod Identity path."
  }
}

run "cluster_compatibility_opt_ins" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                                   = "test-cluster"
    vpc_id                                 = "vpc-12345678"
    subnet_ids                             = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled             = false
    oidc_provider_creation_enabled         = true
    vpc_resource_controller_policy_enabled = true
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 1 && length(data.tls_certificate.oidc) == 1
    error_message = "IRSA opt-in must restore both the provider and its TLS lookup."
  }
  assert {
    condition     = contains(module.cluster_role.managed_policy_arns, "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController") && contains(module.cluster_role.managed_policy_arns, "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy")
    error_message = "The VPC controller opt-in must add its policy without dropping the EKS policy."
  }
}

run "composite_forwards_irsa_opt_in" {
  command = apply
  variables {
    name                                   = "test-cluster"
    region                                 = "us-east-2"
    vpc_id                                 = "vpc-12345678"
    subnet_ids                             = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled             = false
    oidc_provider_creation_enabled         = true
    vpc_resource_controller_policy_enabled = true
  }
  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/MOCK"
    error_message = "The composite must forward the IRSA opt-in and publish the created provider ARN."
  }
  assert {
    condition     = output.oidc_issuer_url == "https://oidc.eks.us-east-2.amazonaws.com/id/MOCK"
    error_message = "The EKS issuer output must remain available."
  }
}

run "node_image_pulls_preserve_bootstrap_permissions" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    cluster_name = "test-cluster"
    name         = "system"
    subnet_ids   = ["subnet-0a", "subnet-0b"]
  }
  assert {
    condition = toset(module.node_role[0].managed_policy_arns) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    ])
    error_message = "Nodes need worker, CNI and pull-only permissions without default ECR ReadOnly or SSM access."
  }
}
