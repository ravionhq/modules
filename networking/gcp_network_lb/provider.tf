# Credentials come from Application Default Credentials. Project and region are
# always explicit so a runner in another project cannot change where resources
# land.
provider "google" {
  project        = var.project_id
  region         = var.region
  default_labels = local.labels
}
