################################################################################
# Component bucket
################################################################################

# Holds the component scripts builds download. Versioned, so a script a newer
# apply replaced stays readable by its generation for
# component_retention_days.
resource "google_storage_bucket" "components" {
  name                        = local.component_bucket_name
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = var.component_retention_days
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_storage_bucket_object" "components" {
  for_each = local.component_objects

  bucket       = google_storage_bucket.components.name
  name         = each.value.object
  content      = local.component_scripts[each.key]
  content_type = "text/x-shellscript"
}
