################################################################################
# Target Group
#
# Every load balancer output is null when var.listener_arn is null, so a worker
# or cron stack that uses this module for an ECR repository or Fargate profile
# still resolves them. one() is the null-safe read of a count = 0/1 resource.
################################################################################

output "target_group_arn" {
  description = "ARN of the target group, or null when the load balancer is disabled. Passed to the workload chart as targetGroupArns so the AWS Load Balancer Controller registers the Service's pod IPs into it."
  value       = one(aws_lb_target_group.this[*].arn)
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, for CloudWatch ApplicationELB metrics (null if the load balancer is disabled)."
  value       = one(aws_lb_target_group.this[*].arn_suffix)
}

output "target_group_name" {
  description = "Name of the target group (null if the load balancer is disabled)."
  value       = one(aws_lb_target_group.this[*].name)
}

################################################################################
# Listener Rule
################################################################################

output "listener_rule_arn" {
  description = "ARN of the listener rule routing requests to the target group (null if the load balancer is disabled)."
  value       = one(aws_lb_listener_rule.this[*].arn)
}

output "listener_rule_priority" {
  description = "Priority assigned to the listener rule, whether configured or auto-assigned by AWS (null if the load balancer is disabled)."
  value       = one(aws_lb_listener_rule.this[*].priority)
}

################################################################################
# Load Balancer
################################################################################

output "load_balancer_arn" {
  description = "ARN of the shared load balancer the listener belongs to (null if the load balancer is disabled)."
  value       = one(data.aws_lb.attached[*].arn)
}

output "load_balancer_dns_name" {
  description = "DNS name of the shared load balancer serving this workload (null if the load balancer is disabled)."
  value       = one(data.aws_lb.attached[*].dns_name)
}

output "load_balancer_zone_id" {
  description = "Route 53 hosted zone ID of the shared load balancer, for alias records (null if the load balancer is disabled)."
  value       = one(data.aws_lb.attached[*].zone_id)
}

output "load_balancer_arn_suffix" {
  description = "ARN suffix of the shared load balancer, for CloudWatch ApplicationELB metrics (null if the load balancer is disabled)."
  value       = one(data.aws_lb.attached[*].arn_suffix)
}

################################################################################
# Service Addresses
#
# What another workload puts in its configuration to call this service. The
# in-cluster values are derived from the release identity and resolve on the
# first apply, before the Helm deploy has created the Service they name; they
# answer only once that deploy succeeds. They are null unless
# kubernetes_service_enabled is set, which only the web workload does, and
# they do not depend on the load balancer. load_balancer_url is null without
# a listener, like every other load balancer output.
################################################################################

output "service_host" {
  description = "In-cluster DNS name of the workload's Kubernetes Service, <release_name>.<release_namespace>.svc.cluster.local. Resolves inside the cluster once the first Helm deploy has created the Service (null unless kubernetes_service_enabled)."
  value       = local.service_host
}

output "service_port" {
  description = "Port the workload's Kubernetes Service listens on, which is the container port (null unless kubernetes_service_enabled)."
  value       = var.kubernetes_service_enabled ? var.container_port : null
}

output "service_url" {
  description = "In-cluster URL of the workload, scheme from the target group protocol plus service_host and service_port. Prefer it for service-to-service calls: traffic stays in the VPC and the Service routes to same-zone pods (null unless kubernetes_service_enabled)."
  value       = local.service_url
}

output "load_balancer_url" {
  description = "URL of the workload through the shared load balancer. Scheme and port come from the listener; the host is the listener rule's first host-header value without a wildcard, otherwise the load balancer DNS name (null if the load balancer is disabled)."
  value       = local.load_balancer_url
}

################################################################################
# ECR Repository
################################################################################

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository (null if disabled)."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_arn : null
}

output "ecr_repository_name" {
  description = "The name of the ECR repository (null if disabled)."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_name : null
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository (null if disabled)."
  value       = var.ecr_repository_creation_enabled ? module.ecr[0].repository_url : null
}

################################################################################
# Fargate Profile
################################################################################

output "fargate_profile_name" {
  description = "Name of the workload's EKS Fargate profile, or null when disabled."
  value       = one(module.fargate_profile[*].fargate_profile_name)
}

output "fargate_profile_arn" {
  description = "ARN of the workload's EKS Fargate profile, or null when disabled."
  value       = one(module.fargate_profile[*].fargate_profile_arn)
}

################################################################################
# General
################################################################################

output "vpc_id" {
  description = "ID of the VPC the target group was created in."
  value       = var.vpc_id
}

output "region" {
  description = "AWS region where the resources are deployed."
  value       = local.region
}
