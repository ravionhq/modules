mock_provider "aws" {
  # Every node group now carries a launch template; the node group resource
  # validates the id's lt- prefix, which a generated mock value would fail.
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
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
    # Direct submodule use: an administrator is registered by the caller.
    cluster_admin_access_managed_externally = true
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
    name                       = "test-cluster"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
    # Direct submodule use: an administrator is registered by the caller.
    cluster_admin_access_managed_externally = true
    oidc_provider_creation_enabled          = true
    vpc_resource_controller_policy_enabled  = true
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

run "cluster_creator_keeps_no_admin_access_by_default" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                       = "test-cluster"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
    # Direct submodule use: an administrator is registered by the caller.
    cluster_admin_access_managed_externally = true
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "The ephemeral principal that creates the cluster must not become a permanent cluster-admin access entry."
  }
}

run "cluster_creator_admin_opt_in" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                                                = "test-cluster"
    vpc_id                                              = "vpc-12345678"
    subnet_ids                                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled                          = false
    bootstrap_cluster_creator_admin_permissions_enabled = true
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    error_message = "Callers must still be able to keep the creator as an admin at creation time."
  }
}

run "runner_role_trusts_only_ravion_runners_by_default" {
  command = plan
  variables {
    name                       = "test-cluster"
    region                     = "us-east-2"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
  }
  assert {
    condition     = output.ravion_runner_role_trusted_principal_arns == tolist(["arn:aws:iam::123456789012:role/rvn-ci/rvn-ci-*"])
    error_message = "Without an override the cluster-admin runner role must trust only Ravion's per-run pipeline runner roles in this account."
  }
}

run "runner_role_trust_override_replaces_the_default" {
  command = plan
  variables {
    name                                      = "test-cluster"
    region                                    = "us-east-2"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled                = false
    ravion_runner_role_trusted_principal_arns = ["arn:aws:iam::123456789012:role/PlatformAdmins"]
  }
  assert {
    condition     = output.ravion_runner_role_trusted_principal_arns == tolist(["arn:aws:iam::123456789012:role/PlatformAdmins"])
    error_message = "An explicit pattern list must replace the default runner pattern rather than merge with it."
  }
}

run "runner_role_trust_output_is_empty_when_disabled" {
  command = plan
  variables {
    name                                = "test-cluster"
    region                              = "us-east-2"
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled          = false
    ravion_runner_role_creation_enabled = false
    # Someone must still administer the cluster once the runner role is gone.
    access_entries = {
      platform-admins = {
        principal_arn = "arn:aws:iam::123456789012:role/PlatformAdmins"
        policy_associations = {
          cluster-admin = { policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }
  assert {
    condition     = length(output.ravion_runner_role_trusted_principal_arns) == 0
    error_message = "With no runner role there is nothing to trust."
  }
}

run "submodule_refuses_a_cluster_with_no_administrator" {
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
  expect_failures = [aws_eks_cluster.this]
}

run "submodule_accepts_an_access_entry_that_grants_access" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                       = "test-cluster"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
    access_entries = {
      platform-admins = {
        principal_arn = "arn:aws:iam::123456789012:role/PlatformAdmins"
        policy_associations = {
          cluster-admin = { policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "An access entry with a policy association is a valid sole administrator."
  }
}

run "submodule_rejects_a_bare_access_entry_as_the_only_administrator" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                       = "test-cluster"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
    access_entries = {
      nobody = { principal_arn = "arn:aws:iam::123456789012:role/Nobody" }
    }
  }
  expect_failures = [aws_eks_cluster.this]
}

run "composite_runner_role_counts_as_the_administrator" {
  command = plan
  variables {
    name                       = "test-cluster"
    region                     = "us-east-2"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
  }
  assert {
    condition     = length(aws_eks_access_policy_association.ravion_runner_admin) == 1
    error_message = "With the defaults the Ravion Runner role must be the cluster's administrator."
  }
}

run "composite_refuses_to_drop_the_runner_role_without_another_administrator" {
  command = plan
  variables {
    name                                = "test-cluster"
    region                              = "us-east-2"
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled          = false
    ravion_runner_role_creation_enabled = false
  }
  expect_failures = [var.ravion_runner_role_creation_enabled]
}

run "composite_allows_dropping_the_runner_role_when_people_have_access" {
  command = plan
  variables {
    name                                = "test-cluster"
    region                              = "us-east-2"
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled          = false
    ravion_runner_role_creation_enabled = false
    access_entries = {
      platform-admins = {
        principal_arn = "arn:aws:iam::123456789012:role/PlatformAdmins"
        policy_associations = {
          cluster-admin = { policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }
  assert {
    condition     = length(aws_eks_access_entry.ravion_runner) == 0
    error_message = "The runner role must be optional once an operator access entry exists."
  }
}

