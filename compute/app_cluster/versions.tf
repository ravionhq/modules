################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Ravion's own provider, served from Ravion's provider registry. Issues the
    # wildcard certificate and its DNS record (certificate.tf), and the custom
    # domains' certificate and domains (ravion_domains.tf). Pin prereleases
    # explicitly; published packages are immutable.
    ravion = {
      source  = "providers.ravion.com/ravion/ravion"
      version = "= 0.0.3-rc.1"
    }
  }
}
