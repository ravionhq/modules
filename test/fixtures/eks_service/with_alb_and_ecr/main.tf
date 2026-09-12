################################################################################
# EKS Service with ALB and ECR Fixture
#
# Both halves of the module enabled at once: a listener rule and target group
# on a shared ALB listener, plus an ECR repository for the workload's image.
# This is the shape a web service that also owns its image registry gets.
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
# ALB
################################################################################

module "alb" {
  source = "../../../../networking/alb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  http_listener_enabled  = true
  https_listener_enabled = false

  deletion_protection_enabled = false

  tags = local.common_tags
}

################################################################################
# EKS Service
################################################################################

# This fixture explicitly verifies configurable mutable tags used by reusable build-source tags.
#trivy:ignore:AVD-AWS-0031
module "eks_service" {
  source = "../../../../compute/eks_service"

  name   = var.name
  region = var.region
  vpc_id = module.vpc.vpc_id

  # Load balancer half
  container_port = 3000

  listener_arn           = module.alb.http_listener_arn
  listener_rule_priority = 200

  listener_rule_conditions = [
    {
      type   = "path-pattern"
      values = ["/*"]
    }
  ]

  # ECR half
  ecr_repository_creation_enabled = true
  ecr_image_tag_mutability        = "MUTABLE"
  ecr_image_scan_on_push_enabled  = true
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

output "alb_arn" {
  description = "The ARN of the ALB standing in for the cluster's shared load balancer."
  value       = module.alb.alb_arn
}

output "listener_arn" {
  description = "The ARN of the HTTP listener the module attached its rule to."
  value       = module.alb.http_listener_arn
}

output "target_group_arn" {
  description = "The ARN of the target group created by the module."
  value       = module.eks_service.target_group_arn
}

output "target_group_name" {
  description = "The name of the target group created by the module."
  value       = module.eks_service.target_group_name
}

output "listener_rule_arn" {
  description = "The ARN of the listener rule created by the module."
  value       = module.eks_service.listener_rule_arn
}

output "listener_rule_priority" {
  description = "The priority assigned to the listener rule."
  value       = module.eks_service.listener_rule_priority
}

output "load_balancer_arn" {
  description = "The ARN of the load balancer the module resolved from the listener."
  value       = module.eks_service.load_balancer_arn
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer the module resolved from the listener."
  value       = module.eks_service.load_balancer_dns_name
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
