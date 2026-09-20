################################################################################
# The published release
################################################################################

locals {
  release = jsonencode({
    runnerVersion = var.runner_version
    guestImageKey = var.guest_image_key
  })
}

# Promoting a release is writing this parameter. It is a module input rather
# than a command so the release a region runs is reviewed, versioned and
# rolled back the same way every other piece of infrastructure is.
resource "aws_ssm_parameter" "release" {
  region      = var.region
  name        = var.parameter_name
  description = "Sandbox host release: the runner version and guest image every pool in this region boots."
  type        = "String"
  value       = local.release
  overwrite   = true
  tags        = var.tags
}
