# Default Capacity Provider Strategy Tests
#
# AWS rejects default capacity provider strategies that mix Fargate and EC2
# (Auto Scaling group) capacity providers. These tests verify that the default
# strategy always commits to a single family, controlled by
# capacity_provider_default.
#
# Run with: tofu test

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.ecs_optimized_ami
    values = {
      value = "ami-0123456789abcdef0"
    }
  }

  override_data {
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.ecs_instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-cluster-ecs-instance"
    }
  }

  override_resource {
    target = aws_launch_template.ecs
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:launch-template/lt-0123456789abcdef"
      id  = "lt-0123456789abcdef"
    }
  }

  override_resource {
    target = module.ecs_autoscaling.aws_autoscaling_group.this
    values = {
      arn = "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:12345678-1234-1234-1234-123456789012:autoScalingGroupName/test-cluster-ecs"
    }
  }
}

mock_provider "ravion" {}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
}

################################################################################
# Implicit family selection (capacity_provider_default = null)
################################################################################

# Fargate only (module defaults): default strategy is FARGATE only
run "defaults_to_fargate" {
  command = plan

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy should contain exactly one entry"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "FARGATE"])
    error_message = "Default strategy should contain FARGATE"
  }
}

# Fargate + Fargate Spot: both share the default strategy (same AWS family)
run "fargate_and_spot_share_default_strategy" {
  command = plan

  variables {
    fargate_spot_enabled = true
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 2
    error_message = "Default strategy should contain FARGATE and FARGATE_SPOT"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "FARGATE_SPOT"])
    error_message = "Default strategy should contain FARGATE_SPOT"
  }
}

# Fargate disabled, Spot enabled: falls back to FARGATE_SPOT
run "defaults_to_spot_when_fargate_disabled" {
  command = plan

  variables {
    fargate_enabled      = false
    fargate_spot_enabled = true
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy should contain exactly one entry"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "FARGATE_SPOT"])
    error_message = "Default strategy should contain FARGATE_SPOT"
  }
}

# EC2 enabled alongside Fargate (the failed terratest run scenario):
# EC2 wins the default strategy; Fargate stays attached but out of the strategy
run "ec2_wins_default_strategy" {
  command = plan

  variables {
    ec2_instance_type    = "t3.medium"
    fargate_enabled      = true
    fargate_spot_enabled = true
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy must not mix Fargate and EC2 capacity providers"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "test-cluster-ec2"])
    error_message = "Default strategy should contain the EC2 capacity provider"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "FARGATE should still be attached to the cluster"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "FARGATE_SPOT should still be attached to the cluster"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "test-cluster-ec2")
    error_message = "The EC2 capacity provider should be attached to the cluster"
  }
}

################################################################################
# Explicit family selection
################################################################################

# EC2 enabled but Fargate explicitly chosen as the default family
run "explicit_fargate_family_with_ec2_enabled" {
  command = plan

  variables {
    ec2_instance_type         = "t3.medium"
    capacity_provider_default = "fargate"
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy should contain exactly one entry"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "FARGATE"])
    error_message = "Default strategy should contain FARGATE when the fargate family is chosen explicitly"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "test-cluster-ec2")
    error_message = "The EC2 capacity provider should still be attached to the cluster"
  }
}

# Fargate Spot explicitly chosen even though Fargate is enabled
run "explicit_spot_family" {
  command = plan

  variables {
    fargate_enabled           = true
    fargate_spot_enabled      = true
    capacity_provider_default = "fargate_spot"
  }

  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy should contain exactly one entry"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider == "FARGATE_SPOT"])
    error_message = "Default strategy should contain only FARGATE_SPOT when the fargate_spot family is chosen explicitly"
  }
}

################################################################################
# Validation
################################################################################

run "invalid_family_value" {
  command = plan

  variables {
    capacity_provider_default = "bogus"
  }

  expect_failures = [var.capacity_provider_default]
}

run "ec2_family_requires_ec2_enabled" {
  command = plan

  variables {
    capacity_provider_default = "ec2"
  }

  expect_failures = [var.capacity_provider_default]
}

run "fargate_family_requires_fargate_enabled" {
  command = plan

  variables {
    fargate_enabled           = false
    fargate_spot_enabled      = true
    capacity_provider_default = "fargate"
  }

  expect_failures = [var.capacity_provider_default]
}

run "spot_family_requires_spot_enabled" {
  command = plan

  variables {
    capacity_provider_default = "fargate_spot"
  }

  expect_failures = [var.capacity_provider_default]
}
