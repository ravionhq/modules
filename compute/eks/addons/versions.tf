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
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    # Ravion's own provider, served from Ravion's provider registry. Used only by
    # beacon.tf, to mint the Operator agent credential server-side.
    # TEMP: pointed at the local dev registry tunnel while providers.ravion.com
    # is not yet live — restore that hostname when the real registry exists.
    ravion = {
      source  = "provider-cf.siddharthsuresh.dev/ravion/ravion"
      version = "~> 1.0"
    }
  }
}
