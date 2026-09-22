################################################################################
# Node and network hardening defaults
#
# Managed nodes must launch with an encrypted root volume and an IMDS hop limit
# of 1 without any caller input, the VPC CNI must enforce NetworkPolicy, and
# control plane logs must outlive the usual compliance evidence window. Every
# check runs against a plan with mocked providers.
################################################################################

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
  mock_data "aws_region" {
    defaults = { region = "us-east-2", name = "us-east-2" }
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
}

mock_provider "tls" {}

mock_provider "external" {
  mock_data "external" {
    defaults = { result = { exists = "false", desired_size = "0" } }
  }
}

run "nodes_launch_hardened_by_default" {
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
    condition     = length(aws_launch_template.this) == 1 && length(aws_eks_node_group.this.launch_template) == 1
    error_message = "The defaults need a launch template; the EKS-managed one cannot encrypt the root volume or lower the IMDS hop limit."
  }
  assert {
    condition     = aws_launch_template.this[0].metadata_options[0].http_tokens == "required" && aws_launch_template.this[0].metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Nodes must require IMDSv2 with a hop limit of 1 so pods cannot read the node's instance credentials."
  }
  assert {
    condition     = aws_launch_template.this[0].block_device_mappings[0].device_name == "/dev/xvda" && aws_launch_template.this[0].block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "The root volume must be encrypted regardless of the account's EBS-encryption-by-default setting."
  }
  assert {
    condition     = aws_launch_template.this[0].block_device_mappings[0].ebs[0].kms_key_id == null
    error_message = "Without a customer-managed key the AWS-managed EBS key must be used."
  }
}

run "customer_managed_key_and_windows_root_device" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    cluster_name    = "test-cluster"
    name            = "windows"
    subnet_ids      = ["subnet-0a", "subnet-0b"]
    ami_type        = "WINDOWS_CORE_2022_x86_64"
    ebs_kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  }
  assert {
    condition     = aws_launch_template.this[0].block_device_mappings[0].device_name == "/dev/sda1"
    error_message = "Windows AMIs mount the root volume at /dev/sda1; naming /dev/xvda would attach a second, unused disk."
  }
  assert {
    condition     = aws_launch_template.this[0].block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this[0].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "A customer-managed key must be honoured on the encrypted root volume."
  }
}

run "opting_out_of_hardening_restores_the_managed_template" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    cluster_name                         = "test-cluster"
    name                                 = "legacy"
    subnet_ids                           = ["subnet-0a", "subnet-0b"]
    ebs_encryption_enabled               = false
    metadata_http_put_response_hop_limit = 2
  }
  assert {
    condition     = length(aws_launch_template.this) == 0
    error_message = "A caller that turns both hardening defaults off and customizes nothing else must fall back to the EKS-managed launch template."
  }
}

run "composite_forwards_hardening_to_the_system_node_group" {
  command = plan
  variables {
    name                       = "test-cluster"
    region                     = "us-east-2"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-0a", "subnet-0b"]
    secrets_encryption_enabled = false
  }
  assert {
    condition     = module.system_node_group.launch_template_id != null
    error_message = "The composite's default system node group must carry the hardened launch template."
  }
}

run "cni_enforces_network_policy_by_default" {
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
    condition     = jsondecode(aws_eks_addon.vpc_cni.configuration_values).enableNetworkPolicy == "true"
    error_message = "NetworkPolicy objects are ignored unless the VPC CNI enforces them, so enforcement must be on by default."
  }
  assert {
    condition     = aws_cloudwatch_log_group.cluster[0].retention_in_days == 365
    error_message = "Control plane audit and authenticator logs must be kept for a year by default."
  }
}

run "explicit_cni_configuration_wins_and_enforcement_can_be_disabled" {
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
    vpc_cni_addon_configuration_values      = "{\"env\":{\"ENABLE_PREFIX_DELEGATION\":\"true\"}}"
  }
  assert {
    condition     = aws_eks_addon.vpc_cni.configuration_values == "{\"env\":{\"ENABLE_PREFIX_DELEGATION\":\"true\"}}"
    error_message = "An explicit CNI configuration document must be passed through untouched."
  }
}

run "network_policy_enforcement_off" {
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
    network_policy_enabled                  = false
  }
  # configuration_values is computed, so the mock invents a value where the
  # real provider would plan null; assert only that no enableNetworkPolicy
  # document is generated.
  assert {
    condition     = !can(jsondecode(aws_eks_addon.vpc_cni.configuration_values).enableNetworkPolicy)
    error_message = "Turning enforcement off must not write an enableNetworkPolicy document to the CNI add-on."
  }
}
