# ECS Cluster Load Balancer Tests
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
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  # Override ALB/NLB resources so mock ARNs are valid
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
    target = aws_launch_template.ecs
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:launch-template/lt-0123456789abcdef"
      id  = "lt-0123456789abcdef"
    }
  }

  override_resource {
    target = module.ecs_instance_security_group.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-ecs123456789"
      id  = "sg-ecs123456789"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.ecs_optimized_ami
    values = {
      value = "ami-0123456789abcdef0"
    }
  }

  override_resource {
    target = module.ecs_autoscaling.aws_autoscaling_group.this
    values = {
      arn = "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:12345678-1234-1234-1234-123456789012:autoScalingGroupName/test-cluster-ecs"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.ecs_instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-cluster-ecs-instance"
    }
  }

  override_resource {
    target = module.public_alb.module.security_group.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-publicalb123456"
      id  = "sg-publicalb123456"
    }
  }

  override_resource {
    target = module.private_alb.module.security_group.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-privatealb123456"
      id  = "sg-privatealb123456"
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

  override_resource {
    target = module.public_nlb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/test-public-nlb/1234567890123458"
      arn_suffix = "net/test-public-nlb/1234567890123458"
      dns_name   = "test-public-nlb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z26RNL4JYFTOTI"
    }
  }

  override_resource {
    target = module.private_nlb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/test-private-nlb/1234567890123459"
      arn_suffix = "net/test-private-nlb/1234567890123459"
      dns_name   = "test-private-nlb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z26RNL4JYFTOTI"
    }
  }
}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
}

################################################################################
# ALB Tests
################################################################################

# Test 21: Public ALB disabled by default
run "public_alb_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.public_alb) == 0
    error_message = "Public ALB should not be created by default"
  }
}

# Test 22: Public ALB enabled
run "public_alb_enabled" {
  command = plan

  variables {
    public_albs       = [{}]
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
  }

  assert {
    condition     = length(module.public_alb) == 1
    error_message = "Public ALB should be created when enabled"
  }
}

# Test 23: Public ALB with HTTPS
run "public_alb_with_https" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
    public_albs = [{
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    }]
  }

  assert {
    condition     = length(module.public_alb) == 1
    error_message = "Public ALB should be created"
  }
}

# Test 24: Public ALB custom settings
run "public_alb_custom_settings" {
  command = plan

  variables {
    public_subnet_ids                         = ["subnet-public1", "subnet-public2"]
    load_balancer_deletion_protection_enabled = false
    public_albs = [{
      idle_timeout        = 120
      ingress_cidr_blocks = ["10.0.0.0/8"]
    }]
  }

  assert {
    condition     = length(module.public_alb) == 1
    error_message = "Public ALB should be created with custom settings"
  }
}

# Test 25: Private ALB disabled by default
run "private_alb_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.private_alb) == 0
    error_message = "Private ALB should not be created by default"
  }
}

# Test 26: Private ALB enabled
run "private_alb_enabled" {
  command = plan

  variables {
    private_albs = [{}]
  }

  assert {
    condition     = length(module.private_alb) == 1
    error_message = "Private ALB should be created when enabled"
  }
}

# Test 27: Private ALB with HTTPS
run "private_alb_with_https" {
  command = plan

  variables {
    private_albs = [{
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
    }]
  }

  assert {
    condition     = length(module.private_alb) == 1
    error_message = "Private ALB should be created with HTTPS"
  }
}

# Test 28: Private ALB custom settings
run "private_alb_custom_settings" {
  command = plan

  variables {
    load_balancer_deletion_protection_enabled = true
    private_albs = [{
      idle_timeout        = 90
      ingress_cidr_blocks = ["192.168.0.0/16"]
    }]
  }

  assert {
    condition     = length(module.private_alb) == 1
    error_message = "Private ALB should be created with custom settings"
  }
}

# Test 28b: Private ALB ingress rules referencing source security groups
run "private_alb_ingress_security_groups" {
  command = plan

  variables {
    private_albs = [{
      https_enabled              = true
      certificate_arns           = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
      ingress_security_group_ids = ["sg-0123456789abcdef0"]
    }]
  }

  assert {
    condition     = length(module.private_alb) == 1
    error_message = "Private ALB should be created with ingress security groups"
  }
}

# Test 28c: Public ALB ingress rules referencing source security groups
run "public_alb_ingress_security_groups" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
    public_albs = [{
      https_enabled              = true
      certificate_arns           = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"]
      ingress_security_group_ids = ["sg-0123456789abcdef0"]
    }]
  }

  assert {
    condition     = length(module.public_alb) == 1
    error_message = "Public ALB should be created with ingress security groups"
  }
}

# Test 29: Both public and private ALBs
run "both_albs_enabled" {
  command = plan

  variables {
    public_albs       = [{}]
    private_albs      = [{}]
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
  }

  assert {
    condition     = length(module.public_alb) == 1
    error_message = "Public ALB should be created"
  }

  assert {
    condition     = length(module.private_alb) == 1
    error_message = "Private ALB should be created"
  }
}

# Test 31: EC2 with public ALB - security group ingress
run "ec2_with_public_alb_ingress" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    public_albs       = [{}]
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
  }

  assert {
    condition     = length(module.ecs_instance_security_group[0].ingress_rule_ids) == 1
    error_message = "EC2 security group should have ingress rule from public ALB"
  }
}

# Test 32: EC2 with private ALB - security group ingress
run "ec2_with_private_alb_ingress" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    private_albs      = [{}]
  }

  assert {
    condition     = length(module.ecs_instance_security_group[0].ingress_rule_ids) == 1
    error_message = "EC2 security group should have ingress rule from private ALB"
  }
}

# Test 33: EC2 without ALBs - no ALB ingress rules
run "ec2_without_albs_no_ingress" {
  command = plan

  variables {
    ec2_instance_type = "t3.medium"
    public_albs       = []
    private_albs      = []
  }

  assert {
    condition     = length(module.ecs_instance_security_group[0].ingress_rule_ids) == 0
    error_message = "EC2 security group should not have ALB ingress rules when no ALBs exist"
  }
}

################################################################################
# Multiple Load Balancer Tests
################################################################################

run "multiple_public_albs" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
    public_albs = [
      {},
      { name = "custom-alb-name", https_enabled = true, certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"] },
    ]
  }

  assert {
    condition     = length(module.public_alb) == 2
    error_message = "Two public ALBs should be created"
  }

  assert {
    condition     = local.public_alb_names[0] == "test-cluster-pub" && local.public_alb_names[1] == "custom-alb-name"
    error_message = "Public ALB names should use the default for the first entry and the explicit name for the second"
  }
}

run "public_alb_addresses_keyed_by_name" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
    public_albs = [
      { name = "alb-b" },
      { name = "alb-a" },
    ]
  }

  assert {
    condition     = contains(keys(module.public_alb), "alb-a") && contains(keys(module.public_alb), "alb-b")
    error_message = "Public ALB module instances should be keyed by resolved name so addresses stay stable when entries are reordered"
  }

  assert {
    condition     = output.public_albs[0].name == "alb-b" && output.public_albs[1].name == "alb-a"
    error_message = "Public ALB outputs should preserve the input order"
  }
}

run "multiple_private_albs_default_names" {
  command = plan

  variables {
    private_albs = [{}, {}]
  }

  assert {
    condition     = length(module.private_alb) == 2
    error_message = "Two private ALBs should be created"
  }

  assert {
    condition     = local.private_alb_names[0] == "test-cluster-priv" && local.private_alb_names[1] == "test-cluster-priv-2"
    error_message = "Private ALB names should be deterministic"
  }
}

################################################################################
# NLB Tests
################################################################################

run "nlbs_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.public_nlb) == 0 && length(module.private_nlb) == 0
    error_message = "No NLBs should be created by default"
  }
}

run "multiple_public_nlbs" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-public1", "subnet-public2"]
    public_nlbs = [
      { cross_zone_load_balancing_enabled = true },
      { name = "custom-nlb" },
    ]
  }

  assert {
    condition     = length(module.public_nlb) == 2
    error_message = "Two public NLBs should be created"
  }

  assert {
    condition     = local.public_nlb_names[0] == "test-cluster-pub-nlb" && local.public_nlb_names[1] == "custom-nlb"
    error_message = "Public NLB names should use the default for the first entry and the explicit name for the second"
  }
}

run "private_nlb_created" {
  command = plan

  variables {
    private_nlbs = [{}]
  }

  assert {
    condition     = length(module.private_nlb) == 1
    error_message = "Private NLB should be created"
  }
}
