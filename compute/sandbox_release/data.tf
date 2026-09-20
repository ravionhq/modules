################################################################################
# The image this release names
################################################################################

# A release is a pair of coordinates, and an image is what carries both. Looking
# it up here is what turns "publish this release" into a deploy that fails when
# the image was never baked in this region, instead of a parameter that sends
# every pool looking for an AMI that does not exist.
data "aws_ami" "host" {
  count       = var.verify_image ? 1 : 0
  region      = var.region
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "tag:ravion:sandbox-host-image"
    values = ["true"]
  }
  filter {
    name   = "tag:ravion:runner-version"
    values = [var.runner_version]
  }
  filter {
    name   = "tag:ravion:guest-image"
    values = [var.guest_image_key]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
