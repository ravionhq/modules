terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.1"
    }
  }
}
