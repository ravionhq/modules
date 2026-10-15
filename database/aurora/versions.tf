# Ephemeral resources and write-only arguments (master_user_secret_name) need
# OpenTofu >= 1.11.
terraform {
  required_version = ">= 1.11.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
