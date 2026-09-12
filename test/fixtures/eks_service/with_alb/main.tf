################################################################################
# EKS Service with ALB Fixture
#
# The web-shaped configuration: an EKS service wired to a shared ALB listener,
# with no ECR repository. Creates a VPC and an ALB, then instantiates
# compute/eks_service against the ALB's HTTP listener.
#
# There is no EKS cluster here on purpose. The eks_service module only creates
# the AWS-side plumbing for a workload (target group, listener rule, and
# optionally an ECR repository); the pods that register into the target group
# are created by the rvn-eks-web Helm chart, which is covered by the chart
# tests. Standing up a cluster would add ~15 minutes and real cost without
# exercising anything this module owns.
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

  # No NAT Gateway: nothing runs in the private subnets in this fixture, and
  # NAT Gateways are the most expensive part of a terratest VPC.
  nat_gateway_enabled = false

  tags = local.common_tags
}

################################################################################
# ALB
#
# Stands in for the shared ALB that compute/eks/addons provisions for a
# cluster. Only the HTTP listener ARN is consumed by the module under test.
################################################################################

module "alb" {
  source = "../../../../networking/alb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  http_listener_enabled  = true
  https_listener_enabled = false

  # Disable deletion protection so terratest can destroy the ALB.
  deletion_protection_enabled = false

  tags = local.common_tags
}

################################################################################
# EKS Service
#
# Every load-balancer-shaped input is set to a non-default value so the test
# can prove the module forwards it rather than accidentally matching a default.
################################################################################

module "eks_service" {
  source = "../../../../compute/eks_service"

  name   = var.name
  region = var.region
  vpc_id = module.vpc.vpc_id

  # Target group
  container_port                    = 8080
  target_group_protocol             = "HTTP"
  target_group_deregistration_delay = 30
  target_group_slow_start           = 60

  target_group_health_check = {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 20
    timeout             = 7
    healthy_threshold   = 3
    unhealthy_threshold = 4
  }

  target_group_stickiness = {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 3600
  }

  # Listener rule
  listener_arn           = module.alb.http_listener_arn
  listener_rule_priority = 100

  listener_rule_conditions = [
    {
      type   = "path-pattern"
      values = ["/api/*"]
    }
  ]

  # ECR is intentionally left at its default (disabled) so the test can assert
  # every ecr_* output is null.

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

output "alb_dns_name" {
  description = "The DNS name of the ALB."
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "The Route 53 hosted zone ID of the ALB."
  value       = module.alb.alb_zone_id
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB."
  value       = module.alb.alb_arn_suffix
}

output "listener_arn" {
  description = "The ARN of the HTTP listener the module attached its rule to."
  value       = module.alb.http_listener_arn
}

output "target_group_arn" {
  description = "The ARN of the target group created by the module."
  value       = module.eks_service.target_group_arn
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the target group created by the module."
  value       = module.eks_service.target_group_arn_suffix
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

output "load_balancer_zone_id" {
  description = "The Route 53 hosted zone ID of the load balancer the module resolved from the listener."
  value       = module.eks_service.load_balancer_zone_id
}

output "load_balancer_arn_suffix" {
  description = "The ARN suffix of the load balancer the module resolved from the listener."
  value       = module.eks_service.load_balancer_arn_suffix
}

output "service_vpc_id" {
  description = "The VPC ID reported by the module under test."
  value       = module.eks_service.vpc_id
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository (null: repository creation is disabled here)."
  value       = module.eks_service.ecr_repository_arn
}

output "ecr_repository_name" {
  description = "The name of the ECR repository (null: repository creation is disabled here)."
  value       = module.eks_service.ecr_repository_name
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository (null: repository creation is disabled here)."
  value       = module.eks_service.ecr_repository_url
}
