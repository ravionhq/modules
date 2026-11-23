# Credentials come from Application Default Credentials: the runner VM's
# service account on Compute Engine, or GOOGLE_* environment variables
# elsewhere. Project is always explicit so a runner in another project cannot
# change where resources land.
provider "google" {
  project        = var.project_id
  region         = var.region
  default_labels = local.labels
}
