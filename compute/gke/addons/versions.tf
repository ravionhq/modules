################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0"
    }
    helm = {
      source = "hashicorp/helm"
      # take_ownership on helm_release needs 3.1.0 or newer.
      version = ">= 3.1"
    }
  }
}
