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
    helm = {
      source = "hashicorp/helm"
      # take_ownership on helm_release needs 3.1.0 or newer.
      version = ">= 3.1"
    }
    # Ravion's own provider, served from Ravion's provider registry. Used by
    # ravion_operator.tf, to mint the Ravion Operator credential server-side,
    # and by ravion_domains.tf when var.use_ravion_managed_domains = true.
    # Pin prereleases explicitly; published packages are immutable.
    ravion = {
      source  = "providers.ravion.com/ravion/ravion"
      version = "= 0.0.3-rc.1"
    }
  }
}
