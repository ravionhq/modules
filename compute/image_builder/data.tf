data "aws_region" "current" {}

data "aws_partition" "current" {}

# The newest image matching the lookup at apply time. Only the parent_image
# output reads it: a deploy looks the parent image up again when it starts, so
# a newer image reaches the next deploy without an apply.
data "aws_ami" "parent" {
  count = local.parent_image_lookup_enabled ? 1 : 0

  region      = local.region
  most_recent = true
  owners      = var.parent_image_lookup.owners

  filter {
    name   = "name"
    values = [var.parent_image_lookup.name]
  }

  filter {
    name   = "architecture"
    values = [var.parent_image_lookup.architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
