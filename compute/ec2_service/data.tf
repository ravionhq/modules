################################################################################
# Data Sources
################################################################################

# Architecture of the selected instance type, used to pick the matching
# default AMI. No user input needed: the instance type determines it.
data "aws_ec2_instance_type" "selected" {
  count = var.ami_id == null ? 1 : 0

  instance_type = var.instance_type
}

# Latest Amazon Linux 2023 AMI for the instance type's CPU architecture
data "aws_ssm_parameter" "al2023_ami" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-${local.cpu_architecture}"
}

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS partition
data "aws_partition" "current" {}
