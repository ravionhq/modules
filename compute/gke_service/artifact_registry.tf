################################################################################
# Artifact Registry Repository
#
# Optional. Holds this workload's container images when Ravion builds them
# (the Dockerfile and Railpack build sources). The cluster's node service
# account reads every repository in the project (compute/gke grants it
# roles/artifactregistry.reader), so pods pull from it with no pull secret.
################################################################################

# Left enabled on destroy: other workloads in the project may use it.
resource "google_project_service" "artifactregistry" {
  count = var.artifact_registry_repository_creation_enabled ? 1 : 0

  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "this" {
  count = var.artifact_registry_repository_creation_enabled ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = local.artifact_registry_repository_id
  description   = "Container images for ${var.name}"
  format        = "DOCKER"
  labels        = local.labels

  docker_config {
    immutable_tags = var.artifact_registry_immutable_tags_enabled
  }

  # INHERITED scans pushes when the Container Scanning API is enabled on the
  # project; DISABLED never scans this repository.
  vulnerability_scanning_config {
    enablement_config = var.artifact_registry_vulnerability_scanning_enabled ? "INHERITED" : "DISABLED"
  }

  # Keep the most recent image versions and delete the rest, the Artifact
  # Registry form of the ECR default lifecycle policy's image cap. KEEP
  # policies win over DELETE policies, so the newest versions always survive.
  cleanup_policy_dry_run = false

  dynamic "cleanup_policies" {
    for_each = var.artifact_registry_cleanup_policies_enabled ? [true] : []

    content {
      id     = "delete-old"
      action = "DELETE"

      condition {
        tag_state = "ANY"
      }
    }
  }

  dynamic "cleanup_policies" {
    for_each = var.artifact_registry_cleanup_policies_enabled ? [true] : []

    content {
      id     = "keep-recent"
      action = "KEEP"

      most_recent_versions {
        keep_count = var.artifact_registry_max_image_count
      }
    }
  }

  depends_on = [google_project_service.artifactregistry]
}

locals {
  artifact_registry_repository_id = coalesce(var.artifact_registry_repository_id, var.name)
}
