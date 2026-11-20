################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  cpu_architecture = contains(data.aws_ec2_instance_type.selected.supported_architectures, "arm64") ? "arm64" : "x86_64"

  default_ami_parameter_names = var.ami_id == null ? {
    "ubuntu-24.04" = "/aws/service/canonical/ubuntu/server/24.04/stable/current/${local.cpu_architecture == "arm64" ? "arm64" : "amd64"}/hvm/ebs-gp3/ami-id"
    "al2023"       = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.cpu_architecture}"
  } : {}

  ami_id = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.default_ami[0].value)

  # Default login user for the base image, for SSH. Session Manager logs in as ssm-user.
  login_user = var.ami_id != null ? null : (var.operating_system == "al2023" ? "ec2-user" : "ubuntu")

  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/dev_box"
  }

  tags = merge(local.default_tags, var.tags)
}
