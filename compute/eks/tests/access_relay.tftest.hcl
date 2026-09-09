# All operations are mocked. No AWS apply or Kubernetes connectivity required.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-12345678", map_public_ip_on_launch = false }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_eks_cluster" {
    defaults = { version = "1.35" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/relay-test"
      endpoint              = "https://test.eks.amazonaws.com"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/test" }] }]
    }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-read" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0" }
  }
}
mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = { certificates = [{
      sha1_fingerprint     = "0123456789012345678901234567890123456789"
      cert_pem             = "mock", is_ca = true, issuer = "mock", max_path_length = 0
      not_after            = "2030-01-01T00:00:00Z", not_before = "2020-01-01T00:00:00Z"
      public_key_algorithm = "RSA", serial_number = "1", signature_algorithm = "SHA256-RSA"
      subject              = "mock", version = 3
    }] }
  }
}

variables {
  name                        = "relay-test"
  region                      = "us-east-2"
  vpc_id                      = "vpc-12345678"
  subnet_ids                  = ["subnet-12345678", "subnet-23456789"]
  ravion_integration_role_arn = "arn:aws:iam::123456789012:role/ravion/integration"
  tags = {
    RavionPurpose         = "wrong"
    RavionClusterArn      = "wrong"
    RavionSessionDocument = "wrong"
    RavionAccessRoleArn   = "wrong"
    RavionReadRoleArn     = "wrong"
  }
}

run "dedicated_hardened_arm_relay" {
  command = apply
  assert {
    condition     = aws_instance.ravion_access_relay.instance_type == "t4g.micro" && data.aws_ssm_parameter.ravion_access_ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "The default relay must be small ARM capacity using an ARM64 AL2023 AMI."
  }
  assert {
    condition     = !aws_instance.ravion_access_relay.associate_public_ip_address && aws_instance.ravion_access_relay.metadata_options[0].http_tokens == "required" && aws_instance.ravion_access_relay.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The relay must be private and require IMDSv2."
  }
  assert {
    condition     = one(aws_instance.ravion_access_relay.root_block_device).encrypted && one(aws_instance.ravion_access_relay.root_block_device).volume_type == "gp3" && one(aws_instance.ravion_access_relay.root_block_device).volume_size == 8
    error_message = "The relay requires a minimal encrypted gp3 root disk."
  }
  assert {
    condition     = aws_instance.ravion_access_relay.tags.RavionPurpose == "eks-access-relay" && aws_instance.ravion_access_relay.tags.RavionClusterArn == "arn:aws:eks:us-east-2:123456789012:cluster/relay-test" && aws_instance.ravion_access_relay.tags.RavionSessionDocument == aws_ssm_document.ravion_access.name && aws_instance.ravion_access_relay.tags.RavionAccessRoleArn == output.ravion_access_role_arn && aws_instance.ravion_access_relay.tags.RavionReadRoleArn == output.ravion_access_read_role_arn
    error_message = "User tags must not override discovery identity or access references."
  }
  assert {
    condition     = aws_iam_role_policy_attachment.ravion_access_relay_ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The instance role must only receive SSM core access, not Kubernetes/admin access."
  }
  assert {
    condition     = var.system_node_group.min_size == 2 && var.system_node_group.max_size == 4 && var.system_node_group.capacity_type == "ON_DEMAND" && join(",", var.system_node_group.instance_types) == "t3.medium"
    error_message = "The relay must not replace or change default managed node capacity."
  }
}

run "document_pins_remote_destination" {
  command = plan
  assert {
    condition     = jsondecode(aws_ssm_document.ravion_access.content).sessionType == "Port" && jsondecode(aws_ssm_document.ravion_access.content).properties.type == "LocalPortForwarding" && jsondecode(aws_ssm_document.ravion_access.content).properties.host == "test.eks.amazonaws.com" && jsondecode(aws_ssm_document.ravion_access.content).properties.portNumber == "443"
    error_message = "Sessions must only target this EKS API, not arbitrary remote hosts or a shell."
  }
  assert {
    condition     = keys(jsondecode(aws_ssm_document.ravion_access.content).parameters) == ["localPortNumber"]
    error_message = "Callers may only select a local port."
  }
  assert {
    condition     = aws_eks_access_policy_association.ravion_access_read.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" && join(",", aws_eks_access_entry.ravion_access_read.kubernetes_groups) == "ravion:readers"
    error_message = "Observers must receive read access, never admin/exec."
  }
}

run "exact_integration_trust_and_approved_egress" {
  command = plan
  assert {
    condition = jsondecode(aws_iam_role.ravion_access_read.assume_role_policy) == jsondecode(jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "TrustRavionIntegrationRole"
        Effect    = "Allow"
        Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
        Principal = { AWS = "arn:aws:iam::123456789012:role/ravion/integration" }
        Condition = {
          IpAddress = { "aws:SourceIp" = [
            "35.165.172.23/32", "52.38.126.172/32", "54.200.59.143/32",
            "54.214.167.211/32", "50.112.69.57/32", "184.33.144.157/32",
          ] }
        }
      }]
    }))
    error_message = "Trust must require exactly the integration role AND the six approved /32s for both STS actions; no root, wildcard, extra statement, or IfExists bypass."
  }
  assert {
    condition     = aws_iam_role.ravion_access_read.assume_role_policy == local.ravion_access_assume_role_policy
    error_message = "Read trust must match the shared policy passed to the existing Runner/admin role."
  }
}

run "read_policy_has_no_transport_or_broad_aws_permissions" {
  command = plan
  assert {
    condition     = length(data.aws_iam_policy_document.ravion_access.statement) == 1 && one(data.aws_iam_policy_document.ravion_access.statement).actions == toset(["eks:DescribeCluster"]) && one(data.aws_iam_policy_document.ravion_access.statement).resources == toset(["arn:aws:eks:us-east-2:123456789012:cluster/relay-test"])
    error_message = "Read-role AWS permissions must be only DescribeCluster on the exact cluster, without SSM, discovery, wildcard resources or extra statements."
  }
  assert {
    condition     = output.ravion_access_role_arn == output.ravion_runner_role_arn && aws_eks_access_policy_association.ravion_runner_admin[0].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    error_message = "Deploy access must retain the existing Runner role and cluster-admin association."
  }
}

run "admin_role_can_be_disabled_without_observer_escalation" {
  command = plan
  variables {
    ravion_runner_role_creation_enabled = false
  }
  assert {
    condition     = output.ravion_access_role_arn == null && aws_instance.ravion_access_relay.tags.RavionAccessRoleArn == "" && length(module.ravion_runner_role) == 0
    error_message = "Disabled admin access must be explicitly absent, never replaced with read or instance-role credentials."
  }
  assert {
    condition     = output.ravion_access_read_role_arn != null
    error_message = "Read access must remain independent of admin role creation."
  }
}

run "node_group_disk_stays_independent" {
  command = plan
  variables {
    system_node_group = { disk_size = 80 }
  }
  assert {
    condition     = var.system_node_group.disk_size == 80 && one(aws_instance.ravion_access_relay.root_block_device).volume_size == 8
    error_message = "Relay disk size must not consume or overwrite node group disk configuration."
  }
}

run "reject_x86_relay" {
  command = plan
  variables { ravion_access_relay_instance_type = "t3.micro" }
  expect_failures = [var.ravion_access_relay_instance_type]
}

run "reject_public_only_api" {
  command = plan
  variables { endpoint_private_access_enabled = false }
  expect_failures = [aws_instance.ravion_access_relay]
}

run "reject_public_subnet" {
  command = plan
  variables { public_subnet_ids = ["subnet-12345678"] }
  expect_failures = [aws_instance.ravion_access_relay]
}

run "reject_auto_public_ip_subnet" {
  command = plan
  override_data {
    target = data.aws_subnet.ravion_access
    values = { vpc_id = "vpc-12345678", map_public_ip_on_launch = true }
  }
  expect_failures = [aws_instance.ravion_access_relay]
}

run "reject_wrong_vpc_subnet" {
  command = plan
  override_data {
    target = data.aws_subnet.ravion_access
    values = { vpc_id = "vpc-87654321", map_public_ip_on_launch = false }
  }
  expect_failures = [aws_instance.ravion_access_relay]
}

run "reject_cross_account_integration_role" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:iam::999999999999:role/ravion/integration" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_wrong_partition_integration_role" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws-us-gov:iam::123456789012:role/ravion/integration" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_account_root" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:iam::123456789012:root" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_iam_user" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:iam::123456789012:user/ravion" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_role_session" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:sts::123456789012:assumed-role/integration/session" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_wildcard_role" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:iam::123456789012:role/ravion/*" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_single_character_wildcard_role" {
  command = plan
  variables { ravion_integration_role_arn = "arn:aws:iam::123456789012:role/integration?" }
  expect_failures = [var.ravion_integration_role_arn]
}

run "reject_empty_integration_role" {
  command = plan
  variables { ravion_integration_role_arn = "" }
  expect_failures = [var.ravion_integration_role_arn]
}
