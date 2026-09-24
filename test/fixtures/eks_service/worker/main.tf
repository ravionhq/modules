################################################################################
# EKS Service Worker Fixture
#
# The worker/cron-shaped configuration: no listener, so no target group and no
# listener rule, plus an ECR repository for the workload's image. Creates only
# a VPC (the module still requires a vpc_id) and instantiates
# compute/eks_service with listener_arn left null.
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
# EKS Service
#
# listener_arn is omitted entirely, which is what a worker or cron workload
# looks like. Every load-balancer-only input is omitted with it, so this
# fixture also proves those variables all have usable defaults.
################################################################################

module "eks_service" {
  source = "../../../../compute/eks_service"

  name   = var.name
  region = var.region

  # Release teardown wired the way the module definitions wire it. The cluster
  # does not exist in this fixture, so the destroy provisioner takes its
  # "cluster absent, nothing to uninstall" path — which is exactly the branch a
  # destroy after the cluster stack has gone relies on.
  workload_release_cleanup_enabled = true
  cluster_name                     = "${var.name}-cluster"
  ravion_runner_role_arn           = "arn:aws:iam::123456789012:role/${var.name}-cluster-ravion-runner"
  release_name                     = var.name
  release_namespace                = "terratest"
  vpc_id                           = module.vpc.vpc_id

  # ECR repository for the worker's image. Non-default values are used for
  # tag mutability so the test can prove the setting is forwarded.
  ecr_repository_creation_enabled      = true
  ecr_image_tag_mutability             = "IMMUTABLE"
  ecr_image_scan_on_push_enabled       = true
  ecr_default_lifecycle_policy_enabled = true

  # Required so terratest can destroy the repository even if an image was
  # pushed into it during the test run.
  ecr_force_delete_enabled = true

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "target_group_arn" {
  description = "The ARN of the target group (null: no listener is configured)."
  value       = module.eks_service.target_group_arn
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the target group (null: no listener is configured)."
  value       = module.eks_service.target_group_arn_suffix
}

output "target_group_name" {
  description = "The name of the target group (null: no listener is configured)."
  value       = module.eks_service.target_group_name
}

output "listener_rule_arn" {
  description = "The ARN of the listener rule (null: no listener is configured)."
  value       = module.eks_service.listener_rule_arn
}

output "listener_rule_priority" {
  description = "The priority of the listener rule (null: no listener is configured)."
  value       = module.eks_service.listener_rule_priority
}

output "load_balancer_arn" {
  description = "The ARN of the load balancer (null: no listener is configured)."
  value       = module.eks_service.load_balancer_arn
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer (null: no listener is configured)."
  value       = module.eks_service.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "The Route 53 hosted zone ID of the load balancer (null: no listener is configured)."
  value       = module.eks_service.load_balancer_zone_id
}

output "load_balancer_arn_suffix" {
  description = "The ARN suffix of the load balancer (null: no listener is configured)."
  value       = module.eks_service.load_balancer_arn_suffix
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
