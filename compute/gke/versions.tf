################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.12.0"

  cloud {}

  required_providers {
    # 8.0 lets a cluster start without a default node pool (initial_node_count
    # and node_config omitted), so no throwaway pool is created and deleted.
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0"
    }
  }
}
