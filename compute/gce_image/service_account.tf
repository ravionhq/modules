################################################################################
# Builder service account
################################################################################

# The identity of every builder and test VM a deploy starts.
resource "google_service_account" "builder" {
  account_id   = local.builder_account_id
  display_name = "Image builder for ${var.name}"
  description  = "Runs the builder and test VMs of the ${var.name} image builds."

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "builder_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.builder.member
}

resource "google_project_iam_member" "builder" {
  for_each = toset(var.builder_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.builder.member
}

resource "google_storage_bucket_iam_member" "builder_components" {
  bucket = google_storage_bucket.components.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.builder.member
}

resource "google_storage_bucket_iam_member" "builder_readers" {
  for_each = toset(var.builder_bucket_readers)

  bucket = each.value
  role   = "roles/storage.objectViewer"
  member = google_service_account.builder.member
}

# Starting a VM that runs as the builder service account needs actAs on it.
resource "google_service_account_iam_member" "deployers" {
  for_each = toset(var.deployer_members)

  service_account_id = google_service_account.builder.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
