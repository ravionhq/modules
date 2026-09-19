data "aws_region" "current" {}

data "aws_partition" "current" {}

# The newest image matching the lookup, resolved at plan time: the recipe pins
# the id it finds, so a newer parent image is a new recipe on the next apply.
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
