################################################################################
# IAM Role for ECS EC2 Instances
################################################################################

resource "aws_iam_role" "ecs_instance" {
  count = local.enable_ec2 ? 1 : 0

  name = "${var.name}-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  count = local.enable_ec2 ? 1 : 0

  role       = aws_iam_role.ecs_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  count = local.enable_ec2 ? 1 : 0

  role       = aws_iam_role.ecs_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  count = local.enable_ec2 ? 1 : 0

  name = "${var.name}-ecs-instance"
  role = aws_iam_role.ecs_instance[0].name

  tags = local.tags
}

################################################################################
# Security Group for ECS EC2 Instances
################################################################################

module "ecs_instance_security_group" {
  count = local.enable_ec2 ? 1 : 0

  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "ecs-instance"
  description = "Security group for ECS EC2 instances"
  vpc_id      = var.vpc_id
  tags        = var.tags

  all_egress_enabled = true

  # For ip_protocol="-1" (all protocols), AWS requires from_port/to_port to
  # be -1; setting them to 0 causes update failures.
  ingress_rules = concat(
    # Allow inbound from each public ALB
    [for name, lb in module.public_alb : {
      description                  = "Allow inbound from public ALB ${name}"
      from_port                    = -1
      to_port                      = -1
      ip_protocol                  = "-1"
      referenced_security_group_id = lb.security_group_id
    }],
    # Allow inbound from each private ALB
    [for name, lb in module.private_alb : {
      description                  = "Allow inbound from private ALB ${name}"
      from_port                    = -1
      to_port                      = -1
      ip_protocol                  = "-1"
      referenced_security_group_id = lb.security_group_id
    }]
  )
}

################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "ecs" {
  count = local.enable_ec2 ? 1 : 0

  name = "${var.name}-ecs"

  image_id      = var.ec2_ami_id != null ? var.ec2_ami_id : data.aws_ssm_parameter.ecs_optimized_ami[0].value
  instance_type = var.ec2_instance_type
  key_name      = var.ec2_key_name

  user_data = local.ecs_user_data

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance[0].arn
  }

  vpc_security_group_ids = concat(
    [module.ecs_instance_security_group[0].security_group_id],
    var.ec2_security_group_ids
  )

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.ec2_root_volume_size
      volume_type           = var.ec2_root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.ec2_imdsv2_enabled ? "required" : "optional"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = "${var.name}-ecs"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = "${var.name}-ecs"
    })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Auto Scaling Group
################################################################################

module "ecs_autoscaling" {
  count  = local.enable_ec2 ? 1 : 0
  source = "../autoscaling"

  name                = "${var.name}-ecs"
  vpc_zone_identifier = var.private_subnet_ids

  # Capacity
  min_size         = var.ec2_min_size
  max_size         = var.ec2_max_size
  desired_capacity = var.ec2_desired_capacity

  # Use existing launch template (don't create new one)
  launch_template_creation_enabled = false
  launch_template_id               = aws_launch_template.ecs[0].id
  launch_template_version          = "$Latest"

  # ECS integration
  # Note: the autoscaling submodule already ignores desired_capacity changes
  # unconditionally, so no toggle is needed for ECS managed scaling.
  ecs_managed_tag_enabled     = true
  scale_in_protection_enabled = var.ec2_managed_termination_protection_enabled

  # Instance refresh
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
    }
  }

  # Mixed instances policy for Spot support
  mixed_instances_policy = var.ec2_spot_enabled ? {
    instances_distribution = {
      on_demand_base_capacity                  = var.ec2_on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.ec2_on_demand_percentage_above_base
      spot_allocation_strategy                 = "capacity-optimized"
    }
    launch_template_overrides = [
      for instance_type in local.ec2_instance_types : {
        instance_type = instance_type
      }
    ]
  } : null

  tags = merge(local.tags, {
    Name             = "${var.name}-ecs"
    AmazonECSManaged = "true"
  })
}
