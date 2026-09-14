################################################################################
# Service discovery namespace
#
# The Cloud Map private DNS namespace ECS services register in. Separate file
# so these runs are independent of the EC2 and load balancer suites.
################################################################################

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

  override_resource {
    target = aws_service_discovery_private_dns_namespace.this
    values = {
      arn         = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-abcdefghij1234567"
      id          = "ns-abcdefghij1234567"
      hosted_zone = "Z0123456789ABCDEFGHIJ"
    }
  }
}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
}

################################################################################
# Service Discovery Namespace Tests
################################################################################

run "service_discovery_namespace_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.this) == 1
    error_message = "The cluster should create a private DNS namespace by default"
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "test-cluster.internal"
    error_message = "The namespace should default to <cluster name>.internal"
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].vpc == "vpc-12345678"
    error_message = "The namespace should be associated with the cluster VPC"
  }

  assert {
    condition     = output.service_discovery_namespace_name == "test-cluster.internal" && output.service_discovery_namespace_id != null
    error_message = "The namespace name and ID should be exposed as outputs"
  }
}

run "service_discovery_namespace_disabled" {
  command = plan

  variables {
    service_discovery_namespace_enabled = false
  }

  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.this) == 0
    error_message = "No namespace should be created when service discovery is disabled"
  }

  assert {
    condition     = output.service_discovery_namespace_id == null && output.service_discovery_namespace_name == null && output.service_discovery_namespace_arn == null && output.service_discovery_namespace_hosted_zone_id == null
    error_message = "Every namespace output should be null when service discovery is disabled"
  }
}

run "service_discovery_namespace_custom_name" {
  command = plan

  variables {
    service_discovery_namespace_name = "svc.acme.local"
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "svc.acme.local"
    error_message = "An explicit namespace name should be used as given"
  }

  assert {
    condition     = output.service_discovery_namespace_name == "svc.acme.local"
    error_message = "The namespace name output should follow the override"
  }
}

run "service_discovery_namespace_rejects_invalid_name" {
  command = plan

  variables {
    service_discovery_namespace_name = "Acme.Internal."
  }

  expect_failures = [var.service_discovery_namespace_name]
}
