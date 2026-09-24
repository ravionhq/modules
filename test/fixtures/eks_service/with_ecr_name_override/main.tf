################################################################################
# EKS Service with ECR Repository Name Override Fixture
#
# Proves ecr_repository_name wins over var.name when both are set. No listener
# is configured, so this fixture also runs the module through its
# load-balancer-disabled path.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "ecr_repository_name" {
  type        = string
  description = "Repository name that must override var.name for the ECR repository."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../../../networking/vpc"

  name         = var.name
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 2

  nat_gateway_enabled = false

  tags = local.common_tags
}

################################################################################
# EKS Service
################################################################################

# This fixture verifies the module's mutable-tag default alongside the repository name override.
#trivy:ignore:AVD-AWS-0031
module "eks_service" {
  source = "../../../../compute/eks_service"

  name   = var.name
  region = var.region
  vpc_id = module.vpc.vpc_id

  ecr_repository_creation_enabled = true
  ecr_repository_name             = var.ecr_repository_name
  ecr_force_delete_enabled        = true

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository created by the module."
  value       = module.eks_service.ecr_repository_arn
}

output "ecr_repository_name" {
  description = "The name of the ECR repository created by the module."
  value       = module.eks_service.ecr_repository_name
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository created by the module."
  value       = module.eks_service.ecr_repository_url
}
