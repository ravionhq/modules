################################################################################
# OpenTofu/Terraform and Provider Requirements
#
# Ephemeral resources and write-only arguments need OpenTofu >= 1.11.
################################################################################

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
