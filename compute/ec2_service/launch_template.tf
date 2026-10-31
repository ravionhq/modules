################################################################################
# Launch Template
#
# Launch template changes (AMI, user data, volumes) apply to newly
# launched instances only. Existing instances are intentionally never
# replaced by this module so in-place state on them is preserved; recycle
# instances manually when a bootstrap change must roll out.
################################################################################

resource "aws_launch_template" "app" {
  name = var.name

  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = local.user_data

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  network_interfaces {
    associate_public_ip_address = var.public_ip_assignment_enabled
    security_groups = concat(
      [module.instance_security_group.security_group_id],
      var.efs_client_security_group_id != null ? [var.efs_client_security_group_id] : [],
      var.additional_security_group_ids
    )
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.data_volume_creation_enabled ? [1] : []
    content {
      device_name = local.data_volume_device_name

      ebs {
        volume_size           = var.data_volume_size
        volume_type           = var.data_volume_type
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = var.name
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.tags, {
      Name = var.name
    })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !local.load_balancer_creation_enabled || var.app_port != null
      error_message = "The app_port is required when a load balancer is attached."
    }

    precondition {
      condition     = var.deploy_health_check_path == null || var.app_port != null
      error_message = "The app_port is required when deploy_health_check_path is set."
    }

    precondition {
      condition     = !(var.data_volume_creation_enabled && var.efs_enabled) || trimsuffix(var.data_volume_mount_path, "/") != trimsuffix(var.efs_mount_path, "/")
      error_message = "The data_volume_mount_path and efs_mount_path must be different paths."
    }

    precondition {
      condition     = !var.efs_enabled || var.efs_file_system_id != null
      error_message = "The efs_file_system_id is required when efs_enabled is true."
    }

    precondition {
      condition     = var.min_size <= var.max_size
      error_message = "The min_size must not be greater than max_size."
    }

    precondition {
      condition     = var.desired_capacity == null || (var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size)
      error_message = "The desired_capacity must be between min_size and max_size."
    }
  }
}
