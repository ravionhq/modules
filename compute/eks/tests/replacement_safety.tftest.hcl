mock_provider "external" {
  mock_data "external" {
    defaults = { result = { exists = "false", desired_size = "0" } }
  }
}

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

# Regression coverage for upgrades that must never replace a live cluster or
# take its system nodes away. Every run keeps deletion protection off: with it
# on, prevent_destroy would also refuse the test framework's own teardown.

run "create_cluster_with_the_creator_bootstrapped" {
  command = apply
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                                                = "test-cluster"
    vpc_id                                              = "vpc-12345678"
    subnet_ids                                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled                          = false
    deletion_protection_enabled                         = false
    bootstrap_cluster_creator_admin_permissions_enabled = true
  }
}

run "changed_bootstrap_default_does_not_replace_the_cluster" {
  command = plan
  module {
    source = "./modules/eks_cluster"
  }
  variables {
    name                                                = "test-cluster"
    vpc_id                                              = "vpc-12345678"
    subnet_ids                                          = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled                          = false
    deletion_protection_enabled                         = false
    bootstrap_cluster_creator_admin_permissions_enabled = false
    cluster_admin_access_managed_externally             = true
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    error_message = "AWS reads the bootstrap flag only at creation; flipping it must be ignored, not plan a replacement."
  }
}

run "node_groups_get_generated_names_for_blue_green_replacement" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    cluster_name  = "test-cluster"
    name          = "system"
    subnet_ids    = ["subnet-0a", "subnet-0b"]
    node_role_arn = "arn:aws:iam::123456789012:role/nodes"
    min_size      = 1
    desired_size  = 1
    max_size      = 2
  }
  assert {
    condition     = aws_eks_node_group.this.node_group_name_prefix == "system-"
    error_message = "A generated name is what lets a replacement group exist alongside the old one."
  }
  assert {
    condition     = aws_eks_node_group.this.tags["ravion.com/node-group"] == "system"
    error_message = "The logical name tag is how the scaling lookup finds a group whose name is generated."
  }
}

run "node_group_names_leave_room_for_the_generated_suffix" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    cluster_name  = "test-cluster"
    name          = "a-node-group-name-longer-than-36-chars"
    subnet_ids    = ["subnet-0a", "subnet-0b"]
    node_role_arn = "arn:aws:iam::123456789012:role/nodes"
    min_size      = 1
    desired_size  = 1
    max_size      = 2
  }
  expect_failures = [var.name]
}
