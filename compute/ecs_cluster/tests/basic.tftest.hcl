# Basic ECS Module Tests
# Run with: tofu test

# Mock AWS provider with overridden data sources
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

  # Override ECS cluster resources
  override_resource {
    target = aws_ecs_cluster.this
    values = {
      arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
      id  = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
    }
  }

  override_resource {
    target = aws_ecs_capacity_provider.ec2
    values = {
      arn = "arn:aws:ecs:us-east-1:123456789012:capacity-provider/test-cluster-ec2"
      id  = "arn:aws:ecs:us-east-1:123456789012:capacity-provider/test-cluster-ec2"
    }
  }

  # Override EC2 infrastructure resources
  override_resource {
    target = aws_iam_role.ecs_instance
    values = {
      arn = "arn:aws:iam::123456789012:role/test-cluster-ecs-instance"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.ecs_instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-cluster-ecs-instance"
    }
  }

  override_resource {
    target = module.ecs_instance_security_group.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-ecs123456789"
      id  = "sg-ecs123456789"
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

  # Override ALB resources for public ALB module
  override_resource {
    target = module.public_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-public-alb/1234567890123456"
      arn_suffix = "app/test-public-alb/1234567890123456"
      dns_name   = "test-public-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.public_alb.aws_lb_listener.http
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-public-alb/1234567890123456/1234567890123456"
    }
  }

  override_resource {
    target = module.public_alb.aws_lb_listener.https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-public-alb/1234567890123456/6543210987654321"
    }
  }

  override_resource {
    target = module.public_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-publicalb123456"
      id  = "sg-publicalb123456"
    }
  }

  override_resource {
    target = module.public_alb.aws_s3_bucket.access_logs
    values = {
      arn = "arn:aws:s3:::test-public-alb-access-logs-123456789012-us-east-1"
      id  = "test-public-alb-access-logs-123456789012-us-east-1"
    }
  }

  # Override ALB resources for private ALB module
  override_resource {
    target = module.private_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-private-alb/1234567890123457"
      arn_suffix = "app/test-private-alb/1234567890123457"
      dns_name   = "test-private-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.private_alb.aws_lb_listener.http
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-private-alb/1234567890123457/1234567890123457"
    }
  }

  override_resource {
    target = module.private_alb.aws_lb_listener.https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-private-alb/1234567890123457/6543210987654322"
    }
  }

  override_resource {
    target = module.private_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-privatealb123456"
      id  = "sg-privatealb123456"
    }
  }

  override_resource {
    target = module.private_alb.aws_s3_bucket.access_logs
    values = {
      arn = "arn:aws:s3:::test-private-alb-access-logs-123456789012-us-east-1"
      id  = "test-private-alb-access-logs-123456789012-us-east-1"
    }
  }
}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
}

################################################################################
# Basic ECS Cluster Tests
################################################################################

# Test 1: Basic ECS cluster with Fargate (defaults)
run "basic_ecs_cluster" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "test-cluster"
    error_message = "ECS cluster should have the correct name"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster.this.setting : s.name == "containerInsights" && s.value == "enhanced"])
    error_message = "Container Insights should be enhanced by default"
  }
}

# Test 2: Container Insights disabled
run "container_insights_disabled" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster.this.setting : s.name == "containerInsights" && s.value == "disabled"])
    error_message = "Container Insights should be disabled when container_insights is disabled"
  }
}

# Test 3: Container Insights standard mode
run "container_insights_standard" {
  command = plan

  variables {
    container_insights = "enabled"
  }

  assert {
    condition     = anytrue([for s in aws_ecs_cluster.this.setting : s.name == "containerInsights" && s.value == "enabled"])
    error_message = "Container Insights should use standard mode when container_insights is enabled"
  }
}

# Test 4: Resource tagging
run "resource_tagging" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      Project     = "myproject"
    }
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["Environment"] == "test"
    error_message = "ECS cluster should have Environment tag"
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["ManagedBy"] == "terraform"
    error_message = "ECS cluster should have default ManagedBy tag"
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["Module"] == "compute/ecs_cluster"
    error_message = "ECS cluster should have default Module tag"
  }
}

################################################################################
# Fargate Capacity Provider Tests
################################################################################

# Test 4: Fargate enabled by default
run "fargate_enabled_by_default" {
  command = plan

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate capacity provider should be enabled by default"
  }
}

# Test 5: Fargate disabled
run "fargate_disabled" {
  command = plan

  variables {
    fargate_enabled = false
  }

  assert {
    condition     = !contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate capacity provider should not be present when disabled"
  }
}

# Test 6: Fargate Spot enabled
run "fargate_spot_enabled" {
  command = plan

  variables {
    fargate_spot_enabled = true
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate Spot capacity provider should be present when enabled"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate capacity provider should still be present"
  }
}

# Test 7: Fargate Spot disabled by default
run "fargate_spot_disabled_by_default" {
  command = plan

  assert {
    condition     = !contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate Spot capacity provider should not be present by default"
  }
}

# Test 8: Both Fargate and Fargate Spot enabled
run "both_fargate_providers" {
  command = plan

  variables {
    fargate_enabled      = true
    fargate_spot_enabled = true
    fargate_weight       = 1
    fargate_spot_weight  = 2
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate capacity provider should be present"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate Spot capacity provider should be present"
  }
}

################################################################################
# EC2 Capacity Provider Tests
################################################################################

# Test 9: EC2 capacity provider disabled by default
run "ec2_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_ecs_capacity_provider.ec2) == 0
    error_message = "EC2 capacity provider should not be created by default"
  }

  assert {
    condition     = length(module.ecs_autoscaling) == 0
    error_message = "Auto Scaling Group should not be created when EC2 disabled"
  }

  assert {
    condition     = length(aws_launch_template.ecs) == 0
    error_message = "Launch template should not be created when EC2 disabled"
  }

  assert {
    condition     = length(aws_iam_role.ecs_instance) == 0
    error_message = "IAM role should not be created when EC2 disabled"
  }

  assert {
    condition     = length(module.ecs_instance_security_group) == 0
    error_message = "Security group should not be created when EC2 disabled"
  }
}

# Test 10: EC2 capacity provider enabled
run "ec2_capacity_provider_enabled" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
  }

  assert {
    condition     = length(aws_ecs_capacity_provider.ec2) == 1
    error_message = "EC2 capacity provider should be created when instance type provided"
  }

  assert {
    condition     = length(module.ecs_autoscaling) == 1
    error_message = "Auto Scaling Group should be created for EC2 capacity provider"
  }

  assert {
    condition     = length(aws_launch_template.ecs) == 1
    error_message = "Launch template should be created for EC2 capacity provider"
  }

  assert {
    condition     = length(aws_iam_role.ecs_instance) == 1
    error_message = "IAM role should be created for EC2 instances"
  }

  assert {
    condition     = length(module.ecs_instance_security_group) == 1
    error_message = "Security group should be created for EC2 instances"
  }
}

# Test 11: EC2 launch template settings
run "ec2_launch_template_settings" {
  command = plan

  variables {
    ec2_instance_type    = "t3.large"
    ec2_root_volume_size = 50
    ec2_root_volume_type = "gp3"
    ec2_imdsv2_enabled   = true
  }

  assert {
    condition     = aws_launch_template.ecs[0].instance_type == "t3.large"
    error_message = "Launch template should use the specified instance type"
  }

  assert {
    condition     = aws_launch_template.ecs[0].block_device_mappings[0].ebs[0].volume_size == 50
    error_message = "Launch template should use the specified volume size"
  }

  assert {
    condition     = aws_launch_template.ecs[0].block_device_mappings[0].ebs[0].volume_type == "gp3"
    error_message = "Launch template should use the specified volume type"
  }

  assert {
    condition     = aws_launch_template.ecs[0].metadata_options[0].http_tokens == "required"
    error_message = "Launch template should require IMDSv2 when enabled"
  }
}

# Test 12: EC2 IMDSv2 disabled
run "ec2_imdsv2_disabled" {
  command = plan

  variables {
    ec2_instance_type  = "t3.medium"
    ec2_imdsv2_enabled = false
  }

  assert {
    condition     = aws_launch_template.ecs[0].metadata_options[0].http_tokens == "optional"
    error_message = "Launch template should not require IMDSv2 when disabled"
  }
}

# Test 13: EC2 Auto Scaling Group settings
run "ec2_asg_settings" {
  command = plan

  variables {
    ec2_instance_type    = "t3.medium"
    ec2_min_size         = 1
    ec2_max_size         = 5
    ec2_desired_capacity = 2
  }

  assert {
    condition     = module.ecs_autoscaling[0].autoscaling_group_min_size == 1
    error_message = "ASG should have the correct min size"
  }

  assert {
    condition     = module.ecs_autoscaling[0].autoscaling_group_max_size == 5
    error_message = "ASG should have the correct max size"
  }

  assert {
    condition     = module.ecs_autoscaling[0].autoscaling_group_desired_capacity == 2
    error_message = "ASG should have the correct desired capacity"
  }
}

# Test 14: EC2 managed termination protection
run "ec2_termination_protection" {
  command = plan

  variables {
    ec2_instance_type                          = "t3.medium"
    ec2_managed_termination_protection_enabled = true
  }

  assert {
    condition     = module.ecs_autoscaling[0].ecs_capacity_provider_config.managed_termination_protection == "ENABLED"
    error_message = "ASG should have scale-in protection when termination protection is ENABLED"
  }

  assert {
    condition     = aws_ecs_capacity_provider.ec2[0].auto_scaling_group_provider[0].managed_termination_protection == "ENABLED"
    error_message = "Capacity provider should have managed termination protection ENABLED"
  }
}

# Test 15: EC2 managed termination protection disabled
run "ec2_termination_protection_disabled" {
  command = plan

  variables {
    ec2_instance_type                          = "t3.medium"
    ec2_managed_termination_protection_enabled = false
  }

  assert {
    condition     = module.ecs_autoscaling[0].ecs_capacity_provider_config.managed_termination_protection == "DISABLED"
    error_message = "ASG should not have scale-in protection when termination protection is DISABLED"
  }
}

# Test 16: EC2 managed scaling
run "ec2_managed_scaling" {
  command = plan

  variables {
    ec2_instance_type                   = "t3.medium"
    ec2_managed_scaling_enabled         = true
    ec2_managed_scaling_target_capacity = 80
  }

  assert {
    condition     = aws_ecs_capacity_provider.ec2[0].auto_scaling_group_provider[0].managed_scaling[0].status == "ENABLED"
    error_message = "Managed scaling should be enabled"
  }

  assert {
    condition     = aws_ecs_capacity_provider.ec2[0].auto_scaling_group_provider[0].managed_scaling[0].target_capacity == 80
    error_message = "Managed scaling should have correct target capacity"
  }
}

run "ec2_managed_scaling_disabled" {
  command = plan

  variables {
    ec2_instance_type           = "t3.medium"
    ec2_managed_scaling_enabled = false
  }

  assert {
    condition     = aws_ecs_capacity_provider.ec2[0].auto_scaling_group_provider[0].managed_scaling[0].status == "DISABLED"
    error_message = "Managed scaling should be disabled"
  }
}

# Test 17: EC2 with custom AMI
run "ec2_custom_ami" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    ec2_ami_id        = "ami-custom123456789"
  }

  assert {
    condition     = aws_launch_template.ecs[0].image_id == "ami-custom123456789"
    error_message = "Launch template should use the custom AMI ID"
  }
}

# Test 18: EC2 security group egress
run "ec2_security_group_egress" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
  }

  assert {
    condition     = length(module.ecs_instance_security_group) == 1
    error_message = "EC2 instance security group should be created"
  }
}

################################################################################
# EC2 Spot Instance Tests
################################################################################

# Test 19: EC2 Spot disabled by default
run "ec2_spot_disabled_by_default" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    ec2_spot_enabled  = false
  }

  assert {
    condition     = length(module.ecs_autoscaling[0].aws_autoscaling_group.this.mixed_instances_policy) == 0
    error_message = "ASG should not use mixed instances policy when Spot disabled"
  }
}

# Test 20: EC2 Spot enabled
run "ec2_spot_enabled" {
  command = plan

  variables {
    ec2_instance_type                   = "t3.medium"
    ec2_spot_enabled                    = true
    ec2_spot_instance_types             = ["t3.large", "t3.xlarge"]
    ec2_on_demand_base_capacity         = 1
    ec2_on_demand_percentage_above_base = 25
  }

  assert {
    condition     = length(module.ecs_autoscaling[0].aws_autoscaling_group.this.mixed_instances_policy) == 1
    error_message = "ASG should use mixed instances policy when Spot enabled"
  }

  assert {
    condition     = module.ecs_autoscaling[0].aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity == 1
    error_message = "ASG should have correct on-demand base capacity"
  }

  assert {
    condition     = module.ecs_autoscaling[0].aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 25
    error_message = "ASG should have correct on-demand percentage above base"
  }
}











################################################################################
# Combined Configuration Tests
################################################################################


# Test 30: Full configuration with EC2 and Fargate
run "full_configuration" {
  command = plan

  variables {
    container_insights   = "enhanced"
    fargate_enabled      = true
    fargate_spot_enabled = true
    ec2_instance_type    = "t3.medium"
    ec2_min_size         = 0
    ec2_max_size         = 10
    ec2_desired_capacity = 2
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate should be enabled"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate Spot should be enabled"
  }

  assert {
    condition     = length(aws_ecs_capacity_provider.ec2) == 1
    error_message = "EC2 capacity provider should be created"
  }
}




# Test 34: No capacity providers (validation - at least one should be enabled)
run "no_fargate_providers" {
  command = plan

  variables {
    fargate_enabled      = false
    fargate_spot_enabled = false
  }

  assert {
    condition     = !contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE")
    error_message = "Fargate should not be present when disabled"
  }

  assert {
    condition     = !contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate Spot should not be present when disabled"
  }
}

# Test 35: EC2 with additional security groups
run "ec2_additional_security_groups" {
  command = plan

  variables {
    ec2_instance_type      = "t3.medium"
    ec2_security_group_ids = ["sg-additional1", "sg-additional2"]
  }

  assert {
    condition     = contains(aws_launch_template.ecs[0].vpc_security_group_ids, "sg-additional1")
    error_message = "Launch template should include additional security group 1"
  }

  assert {
    condition     = contains(aws_launch_template.ecs[0].vpc_security_group_ids, "sg-additional2")
    error_message = "Launch template should include additional security group 2"
  }
}

# Test 36: EC2 capacity provider with custom weights
run "ec2_custom_weights" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    fargate_enabled   = true
    fargate_weight    = 1
    fargate_base      = 1
    ec2_weight        = 2
    ec2_base          = 0
  }

  # AWS rejects default strategies mixing Fargate and EC2 providers, so the
  # default strategy commits to a single family (EC2 wins when enabled).
  assert {
    condition     = length(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy) == 1
    error_message = "Default strategy should contain only the EC2 capacity provider when EC2 is enabled"
  }
}

# Test 37: EC2 with SSH key
run "ec2_with_key_name" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    ec2_key_name      = "my-ssh-key"
  }

  assert {
    condition     = aws_launch_template.ecs[0].key_name == "my-ssh-key"
    error_message = "Launch template should have the specified key name"
  }
}

# Test 38: EC2 encrypted volumes
run "ec2_encrypted_volumes" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
  }

  assert {
    condition     = aws_launch_template.ecs[0].block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Root volume should be encrypted by default"
  }
}

# Test 39: ASG uses private subnets
run "asg_uses_private_subnets" {
  command = plan

  variables {
    ec2_instance_type  = "t3.medium"
    private_subnet_ids = ["subnet-private1", "subnet-private2", "subnet-private3"]
  }

  assert {
    condition     = length(module.ecs_autoscaling[0].aws_autoscaling_group.this.vpc_zone_identifier) == 3
    error_message = "ASG should be deployed to all private subnets"
  }
}

# Test 40: ECS instance monitoring enabled
run "ec2_detailed_monitoring" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
  }

  assert {
    condition     = aws_launch_template.ecs[0].monitoring[0].enabled == true
    error_message = "EC2 detailed monitoring should be enabled"
  }
}
