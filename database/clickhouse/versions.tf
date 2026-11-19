################################################################################
# OpenTofu/Terraform and Provider Requirements
#
# The user passwords are generated ephemerally and reach Secrets Manager only
# through write-only arguments, so they never land in state or plan files.
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
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1"
    }
  }
}
