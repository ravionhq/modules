data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

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

# The parent image's snapshots, read only for a public build, which they can
# block. The lookup above already reports them for the image it found.
data "aws_ami" "parent_snapshot" {
  count = var.public && !local.parent_image_lookup_enabled && local.parent_image_id != null ? 1 : 0

  region = local.region

  filter {
    name   = "image-id"
    values = [local.parent_image_id]
  }
}

# The header value an endpoint checks, when it is kept somewhere rather than
# given here. EventBridge takes the value itself, not a reference to it, so it
# is read on the deploy that writes the connection: rotating the parameter or
# the secret afterwards reaches the endpoint on the next deploy, not before.
data "aws_ssm_parameter" "notify_header" {
  count = local.notify_enabled && local.notify_secret_source == "parameter_store" ? 1 : 0

  region = local.region
  name   = var.notify_header_parameter
}

data "aws_secretsmanager_secret_version" "notify_header" {
  count = local.notify_enabled && local.notify_secret_source == "secrets_manager" ? 1 : 0

  region    = local.region
  secret_id = var.notify_header_secret
}

# The account setting encrypts every new EBS volume in a region, including the
# copies distribution makes, and no recipe can opt out of it.
data "aws_ebs_encryption_by_default" "current" {
  for_each = var.public ? toset(local.all_regions) : toset([])

  region = each.value
}
