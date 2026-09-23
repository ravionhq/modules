################################################################################
# Image Recipe
################################################################################

resource "aws_imagebuilder_image_recipe" "this" {
  # Deployments mode creates no recipe: each deploy builds its own, from the
  # same components, with that deploy's own parameters.
  count = local.deployments_mode ? 0 : 1

  region            = local.region
  name              = "${var.name}-${local.recipe_hash}"
  description       = var.description
  version           = var.recipe_version
  parent_image      = local.parent_image
  working_directory = var.working_directory
  user_data_base64  = local.user_data == null ? null : base64encode(local.user_data)

  dynamic "component" {
    for_each = local.components

    content {
      component_arn = component.value.data != null ? aws_imagebuilder_component.this[component.value.name].arn : component.value.arn

      dynamic "parameter" {
        for_each = component.value.parameters

        content {
          name  = parameter.key
          value = parameter.value
        }
      }
    }
  }

  dynamic "block_device_mapping" {
    for_each = var.root_volume == null ? [] : [var.root_volume]

    content {
      device_name = block_device_mapping.value.device_name

      ebs {
        delete_on_termination = true
        volume_size           = block_device_mapping.value.size_gb
        volume_type           = block_device_mapping.value.type
        iops                  = block_device_mapping.value.iops
        throughput            = block_device_mapping.value.throughput
        encrypted             = local.root_volume_encrypted
        kms_key_id            = block_device_mapping.value.kms_key_id
      }
    }
  }

  systems_manager_agent {
    uninstall_after_build = var.ssm_agent_uninstall_after_build
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.parent_image != null
      error_message = "Set parent_image or parent_image_lookup."
    }

    precondition {
      condition     = !(var.public && coalesce(local.root_volume_encrypted, false))
      error_message = "A public image cannot be backed by an encrypted snapshot. Leave root_volume.encrypted unset or false when public is true."
    }

    precondition {
      condition     = !var.public || local.parent_image_snapshots != null
      error_message = "A public image cannot be backed by an encrypted snapshot, and the parent image decides that. Set parent_image to an AMI id this account can describe, or use parent_image_lookup, so the encryption is known before the build starts."
    }

    precondition {
      condition     = !var.public || coalesce(local.parent_image_encrypted, false) == false
      error_message = "The parent image is backed by an encrypted snapshot, and every image built on it is encrypted too. Build on an unencrypted parent image, or set public to false."
    }

    precondition {
      condition     = length(local.encrypting_regions) == 0
      error_message = "This account encrypts every new EBS volume by default in ${join(", ", local.encrypting_regions)}, which overrides the recipe and leaves the image unpublishable. Turn EBS encryption by default off there, drop those regions, or set public to false."
    }
  }
}
