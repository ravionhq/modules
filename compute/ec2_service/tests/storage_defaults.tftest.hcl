mock_provider "aws" {
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
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
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/supervised-app-instance"
    }
  }

  override_resource {
    target = module.instance_security_group.aws_security_group.this
    values = {
      id = "sg-12345678"
    }
  }

  override_resource {
    target = aws_launch_template.app
    values = {
      id = "lt-12345678"
    }
  }

  override_resource {
    target = aws_lb_target_group.app
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/supervised-app/1234567890abcdef"
    }
  }
}

variables {
  name          = "storage-defaults"
  region        = "us-east-1"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-12345678"]
  instance_type = "t3.micro"
  ami_id        = "ami-12345678"
  runtime       = "container"
}

run "defaults_to_small_os_disk_and_data_volume" {
  command = plan

  assert {
    condition     = var.root_volume_size == 20 && var.data_volume_creation_enabled == true && var.data_volume_size == 20 && var.data_volume_mount_path == "/data"
    error_message = "The module must default to a 20 GB root volume and a 20 GB data volume mounted at /data."
  }

  assert {
    condition     = length(aws_launch_template.app.block_device_mappings) == 2
    error_message = "The launch template must attach a root volume and a data volume by default."
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.app.block_device_mappings :
      m.device_name == "/dev/xvda" && m.ebs[0].volume_size == 20 && m.ebs[0].encrypted == "true"
    ])
    error_message = "The default root volume must be a 20 GB encrypted disk."
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.app.block_device_mappings :
      m.device_name == "/dev/xvdf" && m.ebs[0].volume_size == 20 && m.ebs[0].encrypted == "true" && m.ebs[0].delete_on_termination == "true"
    ])
    error_message = "The default data volume must be a 20 GB encrypted disk at /dev/xvdf."
  }

  assert {
    condition     = strcontains(base64decode(local.user_data), "mkdir -p /data")
    error_message = "The default user data must format and mount the data volume at /data."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "/data:/data")
    error_message = "Container mode must bind-mount the default data volume into the app container."
  }
}

run "explicit_values_still_win" {
  command = plan

  variables {
    root_volume_size             = 50
    data_volume_creation_enabled = false
  }

  assert {
    condition     = length(aws_launch_template.app.block_device_mappings) == 1
    error_message = "Disabling the data volume must leave only the root volume in the launch template."
  }

  assert {
    condition     = one(aws_launch_template.app.block_device_mappings).device_name == "/dev/xvda" && one(aws_launch_template.app.block_device_mappings).ebs[0].volume_size == 50
    error_message = "An explicit root volume size must override the 20 GB default."
  }

  assert {
    condition     = !strcontains(base64decode(local.user_data), "mkdir -p /data")
    error_message = "User data must not mount a data volume when it is disabled."
  }

  assert {
    condition     = !strcontains(aws_ssm_document.deploy.content, "/data:/data")
    error_message = "Container mode must not bind-mount a data volume when it is disabled."
  }
}

run "explicit_data_volume_settings_still_win" {
  command = plan

  variables {
    root_volume_size             = 30
    data_volume_creation_enabled = true
    data_volume_size             = 100
    data_volume_mount_path       = "/var/lib/app"
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.app.block_device_mappings :
      m.device_name == "/dev/xvda" && m.ebs[0].volume_size == 30
    ])
    error_message = "An explicit root volume size must be kept."
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.app.block_device_mappings :
      m.device_name == "/dev/xvdf" && m.ebs[0].volume_size == 100
    ])
    error_message = "An explicit data volume size must be kept."
  }

  assert {
    condition     = strcontains(base64decode(local.user_data), "mkdir -p /var/lib/app")
    error_message = "An explicit data volume mount path must be kept."
  }
}
