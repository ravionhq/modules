# Dev box module tests — run from module root: tofu test

mock_provider "aws" {
  override_data {
    target = data.aws_ec2_instance_type.selected
    values = {
      supported_architectures = ["x86_64"]
    }
  }

  override_data {
    target = data.aws_ssm_parameter.default_ami
    values = {
      value = "ami-0123456789abcdef0"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_resource {
    target = aws_instance.this
    values = {
      id  = "i-0123456789abcdef0"
      arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    }
  }

  override_resource {
    target = aws_iam_role.auto_stop
    values = {
      arn = "arn:aws:iam::123456789012:role/test-dev-box-stop"
    }
  }
}

variables {
  name          = "test"
  vpc_id        = "vpc-0123456789abcdef0"
  subnet_ids    = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  instance_type = "m7i.large"
}

################################################################################
# Defaults — private, encrypted, Session Manager only
################################################################################

run "defaults" {
  command = plan

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0aaaaaaaaaaaaaaaa"
    error_message = "The dev box must run in the first subnet"
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "No public IP by default"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true && aws_instance.this.root_block_device[0].volume_size == 100 && aws_instance.this.root_block_device[0].volume_type == "gp3"
    error_message = "Root volume must default to an encrypted 100 GiB gp3 volume"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 0
    error_message = "No inbound rules by default"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "Session Manager access must be on by default"
  }

  assert {
    condition     = data.aws_ssm_parameter.default_ami[0].name == "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
    error_message = "Default image must be the latest Ubuntu 24.04 for the instance architecture"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "The instance must use the resolved default AMI"
  }

  assert {
    condition     = output.login_user == "ubuntu"
    error_message = "Ubuntu login user must be ubuntu"
  }

  assert {
    condition     = length(aws_scheduler_schedule.auto_stop) == 0 && length(aws_iam_role.auto_stop) == 0
    error_message = "Auto stop must be off by default"
  }

  assert {
    condition     = output.public_ip == null
    error_message = "public_ip must be null without a public IP"
  }
}

################################################################################
# Amazon Linux on Graviton
################################################################################

run "al2023_arm64" {
  command = plan

  variables {
    instance_type    = "m8g.large"
    operating_system = "al2023"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = {
      supported_architectures = ["arm64"]
    }
  }

  assert {
    condition     = data.aws_ssm_parameter.default_ami[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "Amazon Linux image must match the arm64 architecture"
  }

  assert {
    condition     = output.login_user == "ec2-user"
    error_message = "Amazon Linux login user must be ec2-user"
  }
}

################################################################################
# Custom AMI skips image lookups
################################################################################

run "custom_ami" {
  command = plan

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.default_ami) == 0 && length(data.aws_ec2_instance_type.selected) == 0
    error_message = "A custom AMI must not look up a default image"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0fedcba9876543210"
    error_message = "The instance must use the custom AMI"
  }

  assert {
    condition     = output.login_user == null
    error_message = "Login user is unknown for a custom AMI"
  }
}

################################################################################
# Public SSH access, extra permissions, and auto stop
################################################################################

run "public_ssh_and_auto_stop" {
  command = apply

  variables {
    public_ip_assignment_enabled  = true
    ssh_allowed_cidr_blocks       = ["203.0.113.0/24"]
    key_name                      = "my-key"
    iam_policy_arns               = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    auto_stop_enabled             = true
    auto_stop_timezone            = "America/New_York"
    additional_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == true
    error_message = "Public IP must be assigned when enabled"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh["203.0.113.0/24"].from_port == 22
    error_message = "SSH must be allowed from the configured CIDR"
  }

  assert {
    condition     = contains(aws_instance.this.vpc_security_group_ids, "sg-0123456789abcdef0")
    error_message = "Additional security groups must be attached"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.additional) == 1
    error_message = "Additional IAM policies must be attached"
  }

  assert {
    condition     = aws_scheduler_schedule.auto_stop[0].schedule_expression_timezone == "America/New_York"
    error_message = "Auto stop must use the configured time zone"
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.auto_stop[0].target[0].input).InstanceIds[0] == "i-0123456789abcdef0"
    error_message = "Auto stop must target the dev box"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.auto_stop[0].policy).Statement[0].Resource == "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    error_message = "Auto stop role must only stop the dev box"
  }
}

################################################################################
# Validation
################################################################################

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Not_Valid"
  }

  expect_failures = [var.name]
}

run "rejects_unknown_operating_system" {
  command = plan

  variables {
    operating_system = "windows"
  }

  expect_failures = [var.operating_system]
}

run "rejects_empty_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}
