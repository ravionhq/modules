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
    # wildcard certificate and its DNS record (certificate.tf) and registers
    # the sandbox pool (sandbox_pool.tf). 0.0.4-rc.1 is the first release with
    # ravion_sandbox_pool. Pin prereleases explicitly; published packages are
    # immutable.
    # DEV ONLY, revert before merge: the dev registry's build of the provider.
    ravion = {
      source  = "provider-cf.siddharthsuresh.dev/ravion/ravion"
      version = "= 0.0.4-dev.1"
    }
  }
}
