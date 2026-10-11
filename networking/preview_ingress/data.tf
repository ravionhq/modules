################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

# The VPC's IPv4 ranges bound where the router may open preview connections.
data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_ec2_instance_type" "router" {
  instance_type = var.instance_type
}

# The image the router boots: the one named, or the newest the owner publishes
# for the instance type's architecture.
data "aws_ami" "router" {
  most_recent = var.image_id == null
  owners      = var.image_id == null ? [var.image_owner] : null

  dynamic "filter" {
    for_each = var.image_id == null ? tomap({
      name         = [var.image_name_pattern]
      architecture = data.aws_ec2_instance_type.router.supported_architectures
      state        = ["available"]
      }) : tomap({
      "image-id" = [var.image_id]
    })

    content {
      name   = filter.key
      values = filter.value
    }
  }
}
