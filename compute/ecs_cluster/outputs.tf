################################################################################
# ECS Cluster
################################################################################

output "cluster_id" {
  description = "The ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "The name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

################################################################################
# Capacity Providers
################################################################################

output "fargate_capacity_provider_name" {
  description = "The name of the Fargate capacity provider (null if disabled)."
  value       = var.fargate_enabled ? "FARGATE" : null
}

output "fargate_spot_capacity_provider_name" {
  description = "The name of the Fargate Spot capacity provider (null if disabled)."
  value       = var.fargate_spot_enabled ? "FARGATE_SPOT" : null
}

output "ec2_capacity_provider_name" {
  description = "The name of the EC2 capacity provider (null if disabled)."
  value       = local.enable_ec2 ? aws_ecs_capacity_provider.ec2[0].name : null
}

output "ec2_capacity_provider_arn" {
  description = "The ARN of the EC2 capacity provider (null if disabled)."
  value       = local.enable_ec2 ? aws_ecs_capacity_provider.ec2[0].arn : null
}

################################################################################
# EC2 Infrastructure
################################################################################

output "launch_template_id" {
  description = "The ID of the EC2 launch template (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_launch_template.ecs[0].id : null
}

output "launch_template_arn" {
  description = "The ARN of the EC2 launch template (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_launch_template.ecs[0].arn : null
}

output "autoscaling_group_arn" {
  description = "The ARN of the Auto Scaling Group (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_autoscaling[0].autoscaling_group_arn : null
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_autoscaling[0].autoscaling_group_name : null
}

output "ecs_instance_role_arn" {
  description = "The ARN of the IAM role for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_iam_role.ecs_instance[0].arn : null
}

output "ecs_instance_role_name" {
  description = "The name of the IAM role for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? aws_iam_role.ecs_instance[0].name : null
}

output "ecs_instance_security_group_id" {
  description = "The ID of the security group for ECS EC2 instances (null if EC2 disabled)."
  value       = local.enable_ec2 ? module.ecs_instance_security_group[0].security_group_id : null
}

################################################################################
# Public ALB
################################################################################

output "public_alb_arn" {
  description = "The ARN of the public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn : null
}

output "public_alb_id" {
  description = "The ID of the public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_id : null
}

output "public_alb_dns_name" {
  description = "The DNS name of the public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "The canonical hosted zone ID of the public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "The ARN suffix of the public ALB for CloudWatch Metrics (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "The ID of the public ALB security group (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "The ARN of the public ALB HTTP listener (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "The ARN of the public ALB HTTPS listener (null if HTTPS disabled)."
  value       = var.public_alb_enabled && var.public_alb_https_enabled ? module.public_alb[0].https_listener_arn : null
}

################################################################################
# Private ALB
################################################################################

output "private_alb_arn" {
  description = "The ARN of the private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn : null
}

output "private_alb_id" {
  description = "The ID of the private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_id : null
}

output "private_alb_dns_name" {
  description = "The DNS name of the private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "The canonical hosted zone ID of the private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "The ARN suffix of the private ALB for CloudWatch Metrics (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "The ID of the private ALB security group (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "The ARN of the private ALB HTTP listener (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "The ARN of the private ALB HTTPS listener (null if HTTPS disabled)."
  value       = var.private_alb_enabled && var.private_alb_https_enabled ? module.private_alb[0].https_listener_arn : null
}

################################################################################
# Public NLB
################################################################################

output "public_nlb_arn" {
  description = "The ARN of the public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn : null
}

output "public_nlb_id" {
  description = "The ID of the public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_id : null
}

output "public_nlb_dns_name" {
  description = "The DNS name of the public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "The canonical hosted zone ID of the public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "The ARN suffix of the public NLB for CloudWatch Metrics (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn_suffix : null
}

output "public_nlb_security_group_id" {
  description = "The ID of the public NLB security group (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].security_group_id : null
}

################################################################################
# Private NLB
################################################################################

output "private_nlb_arn" {
  description = "The ARN of the private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn : null
}

output "private_nlb_id" {
  description = "The ID of the private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_id : null
}

output "private_nlb_dns_name" {
  description = "The DNS name of the private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "The canonical hosted zone ID of the private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "The ARN suffix of the private NLB for CloudWatch Metrics (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn_suffix : null
}

output "private_nlb_security_group_id" {
  description = "The ID of the private NLB security group (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].security_group_id : null
}


################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}

################################################################################
# Ravion-managed domains
################################################################################

output "ravion_cluster_certificate_id" {
  description = "Ravion managed-certificate id for the cluster wildcard (null unless use_ravion_managed_domains)."
  value       = local.enable_ravion_domain ? ravion_aws_acm_certificate.cluster[0].id : null
}

output "ravion_cluster_domain_fqdn" {
  description = "Cluster wildcard apex FQDN. Pass to ecs_service as cluster_parent_fqdn."
  value       = local.enable_ravion_domain ? ravion_aws_acm_certificate.cluster[0].domain_name : null
}

output "ravion_cluster_cert_arn" {
  description = "ACM ARN of the cluster wildcard cert."
  value       = local.enable_ravion_domain ? ravion_aws_acm_certificate.cluster[0].arn : null
}

output "ravion_aws_account_id" {
  description = "Pass-through Ravion AwsAccount row id for ecs_service Mode B."
  value       = var.ravion_aws_account_id
}

output "ravion_aws_region" {
  description = "Pass-through Ravion cert region for ecs_service Mode B."
  value       = local.enable_ravion_domain ? coalesce(var.ravion_aws_region, local.region) : null
}

output "ravion_managed_domains_enabled" {
  description = "True when the cluster owns a Ravion wildcard certificate for its selected HTTPS-enabled ALB. Services read this to show/hide managed-domain fields."
  value       = local.enable_ravion_domain
}
