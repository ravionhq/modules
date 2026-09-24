################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.0 is the first release with the per-resource `region` argument, which
      # places every resource in the build region from one provider
      # configuration.
      version = ">= 6.0"
    }
  }
}
