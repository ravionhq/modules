mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-west-2", name = "us-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_cluster" {
    defaults = { version = "1.36" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "1.36.4-20261030" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
}

mock_provider "external" {
  mock_data "external" {
    defaults = { result = { exists = "false", desired_size = "0" } }
  }
}

variables {
  cluster_name  = "test-cluster"
  name          = "system"
  subnet_ids    = ["subnet-0a", "subnet-0b"]
  node_role_arn = "arn:aws:iam::123456789012:role/nodes"
}

run "latest_release_for_cluster_version" {
  command = plan
  module { source = "./modules/eks_node_group" }
  assert {
    condition     = aws_eks_node_group.this.release_version == "1.36.4-20261030" && aws_eks_node_group.this.version == "1.36"
    error_message = "An apply must roll managed nodes onto the recommended AMI, not leave their original release running."
  }
  assert {
    condition     = data.aws_ssm_parameter.ami_release[0].name == "/aws/service/eks/optimized-ami/1.36/amazon-linux-2023/x86_64/standard/recommended/release_version"
    error_message = "An omitted node version must follow the deployed cluster version."
  }
}

run "explicit_arm_node_version" {
  command = plan
  module { source = "./modules/eks_node_group" }
  variables {
    ami_type           = "AL2023_ARM_64_STANDARD"
    kubernetes_version = "1.35"
  }
  assert {
    condition     = data.aws_ssm_parameter.ami_release[0].name == "/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/arm64/standard/recommended/release_version" && length(data.aws_eks_cluster.current) == 0
    error_message = "Select the requested architecture and node Kubernetes version without another cluster lookup."
  }
}

run "custom_ami_is_not_overridden" {
  command = plan
  module { source = "./modules/eks_node_group" }
  variables { ami_type = "CUSTOM" }
  assert {
    condition     = length(data.aws_ssm_parameter.ami_release) == 0 && length(data.aws_eks_cluster.current) == 0
    error_message = "A custom image must not use an Amazon Linux release."
  }
}

run "windows_is_not_overridden" {
  command = plan
  module { source = "./modules/eks_node_group" }
  variables { ami_type = "WINDOWS_CORE_2022_x86_64" }
  assert {
    condition     = length(data.aws_ssm_parameter.ami_release) == 0
    error_message = "Do not use a Linux release for Windows nodes."
  }
}
