################################################################################
# Distribution Configuration
#
# The build region only, with no launch permission: it names and tags the image
# a build produces and leaves it private. Each deploy copies the image to every
# other region, tags it, and publishes it itself.
################################################################################

resource "aws_imagebuilder_distribution_configuration" "this" {
  region      = local.region
  name        = var.name
  description = var.description

  distribution {
    region = local.region

    ami_distribution_configuration {
      name        = local.ami_name
      description = var.ami_description
      ami_tags    = merge(local.tags, var.ami_tags)
    }
  }

  tags = local.tags
}
