################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

data "aws_partition" "current" {}

# Architecture of the selected instance type, used to pick the matching default AMI.
data "aws_ec2_instance_type" "selected" {
  count = var.ami_id == null ? 1 : 0

  instance_type = var.instance_type
}

# Latest public image for the selected operating system and architecture.
data "aws_ssm_parameter" "default_ami" {
  count = var.ami_id == null ? 1 : 0

  name = local.default_ami_parameter_names[var.operating_system]
}
