################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.21 adds linear_configuration / canary_configuration on the
      # aws_ecs_service deployment_configuration block.
      version = ">= 6.21"
    }
    ravion = {
      source  = "providers.ravion.com/ravion/ravion"
      version = "= 0.0.3-rc.1"
    }
  }
}
