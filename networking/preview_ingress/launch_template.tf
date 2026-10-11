################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "router" {
  name = local.router_name

  image_id      = data.aws_ami.router.id
  instance_type = var.instance_type

  user_data = base64encode(local.user_data)

  dynamic "iam_instance_profile" {
    for_each = var.ssm_enabled ? [1] : []
    content {
      arn = aws_iam_instance_profile.router[0].arn
    }
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = var.router_public_ip_enabled
    security_groups             = [aws_security_group.router.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = data.aws_ami.router.root_device_name

    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # The router proves which instance it is with its signed identity document,
  # read over IMDSv2. Nothing on the instance is more than one hop away.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # On the instance from the moment it launches: enrollment reads the tag
  # within seconds of boot.
  tag_specifications {
    resource_type = "instance"
    tags          = local.router_tags
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = local.router_name
    })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = contains(data.aws_ec2_instance_type.router.supported_architectures, data.aws_ami.router.architecture)
      error_message = "The instance type ${var.instance_type} does not run ${data.aws_ami.router.architecture} images. Choose an instance type and an image of the same architecture."
    }

    precondition {
      condition     = contains(keys(local.runner_platforms), data.aws_ami.router.architecture)
      error_message = "The router is released for x86_64 and arm64 images only."
    }
  }
}
