################################################################################
# ECR Repository
#
# Optional. Creates a repository for this workload's container image when
# var.ecr_repository_creation_enabled is true, which is what the module
# definitions set for the Dockerfile and Railpack build sources. The image is
# pulled by the node's instance role (or an image pull secret for a foreign
# registry), so no additional wiring is needed for the pod to pull from it.
################################################################################

module "ecr" {
  count = var.ecr_repository_creation_enabled ? 1 : 0

  source = "../../containers/ecr"

  name = var.ecr_repository_name != null ? var.ecr_repository_name : var.name
  tags = var.tags

  image_tag_mutability       = var.ecr_image_tag_mutability
  image_scan_on_push_enabled = var.ecr_image_scan_on_push_enabled
  force_delete_enabled       = var.ecr_force_delete_enabled

  default_lifecycle_policy_enabled = var.ecr_default_lifecycle_policy_enabled
}
