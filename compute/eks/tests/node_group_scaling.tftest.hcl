mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2", name = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
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
  min_size      = 2
  desired_size  = 2
  max_size      = 4
}

# Apply a mocked existing group before planning a bound change. A plan-only
# fresh resource test would not catch the old ignore_changes regression.
run "create_two_nodes" {
  command = apply
  module {
    source = "./modules/eks_node_group"
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2
    error_message = "A new group must use its initial desired size."
  }
}

run "raise_minimum_above_live_desired" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    min_size     = 4
    desired_size = 4
    max_size     = 6
  }
  override_data {
    target = data.external.scaling
    values = { result = { exists = "true", desired_size = "2" } }
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 4
    error_message = "Raising minimum 2 -> 4 must raise desired 2 -> 4 in the same update."
  }
}

run "preserve_autoscaled_capacity" {
  command = apply
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    max_size = 10
  }
  override_data {
    target = data.external.scaling
    values = { result = { exists = "true", desired_size = "8" } }
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 8
    error_message = "An autoscaler's desired 8 must not reset to the initial desired 2."
  }
}

run "lower_maximum_below_live_desired" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    max_size = 5
  }
  override_data {
    target = data.external.scaling
    values = { result = { exists = "true", desired_size = "8" } }
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 5
    error_message = "Lowering maximum below desired must clamp desired in the same update."
  }
}

run "zero_is_a_valid_live_desired" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    min_size = 0
    max_size = 10
  }
  override_data {
    target = data.external.scaling
    values = { result = { exists = "true", desired_size = "0" } }
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 0
    error_message = "Zero must not fall back to the initial desired size."
  }
}

run "reject_reversed_bounds" {
  command = plan
  module {
    source = "./modules/eks_node_group"
  }
  variables {
    min_size = 5
    max_size = 4
  }
  expect_failures = [aws_eks_node_group.this]
}
