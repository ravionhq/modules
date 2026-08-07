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
# Public ALBs
################################################################################

output "public_albs" {
  description = "All public ALBs with their attributes, in the same order as var.public_albs."
  value = [for name in local.public_alb_names : {
    name               = name
    arn                = module.public_alb[name].alb_arn
    id                 = module.public_alb[name].alb_id
    dns_name           = module.public_alb[name].alb_dns_name
    zone_id            = module.public_alb[name].alb_zone_id
    arn_suffix         = module.public_alb[name].alb_arn_suffix
    security_group_id  = module.public_alb[name].security_group_id
    http_listener_arn  = module.public_alb[name].http_listener_arn
    https_listener_arn = local.public_albs_by_name[name].https_enabled ? module.public_alb[name].https_listener_arn : null
    https_enabled      = local.public_albs_by_name[name].https_enabled
  }]
}

output "public_albs_by_name" {
  description = "Public ALB attributes keyed by load balancer name."
  value = { for name in local.public_alb_names : name => {
    name               = name
    arn                = module.public_alb[name].alb_arn
    id                 = module.public_alb[name].alb_id
    dns_name           = module.public_alb[name].alb_dns_name
    zone_id            = module.public_alb[name].alb_zone_id
    arn_suffix         = module.public_alb[name].alb_arn_suffix
    security_group_id  = module.public_alb[name].security_group_id
    http_listener_arn  = module.public_alb[name].http_listener_arn
    https_listener_arn = local.public_albs_by_name[name].https_enabled ? module.public_alb[name].https_listener_arn : null
    https_enabled      = local.public_albs_by_name[name].https_enabled
  } }
}

output "public_alb_options" {
  description = "Public ALB select options ({label, value} pairs of load balancer names) for module definition forms."
  value       = [for name in local.public_alb_names : { label = name, value = name }]
}

# Deprecated single-ALB outputs (first entry of public_albs); kept for
# consumers that support only one load balancer per type.

output "public_alb_arn" {
  description = "The ARN of the first public ALB (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].alb_arn : null
}

output "public_alb_id" {
  description = "The ID of the first public ALB (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].alb_id : null
}

output "public_alb_dns_name" {
  description = "The DNS name of the first public ALB (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "The canonical hosted zone ID of the first public ALB (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "The ARN suffix of the first public ALB for CloudWatch Metrics (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "The ID of the first public ALB security group (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "The ARN of the first public ALB HTTP listener (null if none)."
  value       = length(local.public_alb_names) > 0 ? module.public_alb[local.public_alb_names[0]].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "The ARN of the first public ALB HTTPS listener (null if HTTPS disabled)."
  value       = length(local.public_alb_names) > 0 && var.public_albs[0].https_enabled ? module.public_alb[local.public_alb_names[0]].https_listener_arn : null
}

################################################################################
# Private ALBs
################################################################################

output "private_albs" {
  description = "All private ALBs with their attributes, in the same order as var.private_albs."
  value = [for name in local.private_alb_names : {
    name               = name
    arn                = module.private_alb[name].alb_arn
    id                 = module.private_alb[name].alb_id
    dns_name           = module.private_alb[name].alb_dns_name
    zone_id            = module.private_alb[name].alb_zone_id
    arn_suffix         = module.private_alb[name].alb_arn_suffix
    security_group_id  = module.private_alb[name].security_group_id
    http_listener_arn  = module.private_alb[name].http_listener_arn
    https_listener_arn = local.private_albs_by_name[name].https_enabled ? module.private_alb[name].https_listener_arn : null
    https_enabled      = local.private_albs_by_name[name].https_enabled
  }]
}

output "private_albs_by_name" {
  description = "Private ALB attributes keyed by load balancer name."
  value = { for name in local.private_alb_names : name => {
    name               = name
    arn                = module.private_alb[name].alb_arn
    id                 = module.private_alb[name].alb_id
    dns_name           = module.private_alb[name].alb_dns_name
    zone_id            = module.private_alb[name].alb_zone_id
    arn_suffix         = module.private_alb[name].alb_arn_suffix
    security_group_id  = module.private_alb[name].security_group_id
    http_listener_arn  = module.private_alb[name].http_listener_arn
    https_listener_arn = local.private_albs_by_name[name].https_enabled ? module.private_alb[name].https_listener_arn : null
    https_enabled      = local.private_albs_by_name[name].https_enabled
  } }
}

output "private_alb_options" {
  description = "Private ALB select options ({label, value} pairs of load balancer names) for module definition forms."
  value       = [for name in local.private_alb_names : { label = name, value = name }]
}

# Deprecated single-ALB outputs (first entry of private_albs); kept for
# consumers that support only one load balancer per type.

output "private_alb_arn" {
  description = "The ARN of the first private ALB (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].alb_arn : null
}

output "private_alb_id" {
  description = "The ID of the first private ALB (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].alb_id : null
}

output "private_alb_dns_name" {
  description = "The DNS name of the first private ALB (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "The canonical hosted zone ID of the first private ALB (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "The ARN suffix of the first private ALB for CloudWatch Metrics (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "The ID of the first private ALB security group (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "The ARN of the first private ALB HTTP listener (null if none)."
  value       = length(local.private_alb_names) > 0 ? module.private_alb[local.private_alb_names[0]].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "The ARN of the first private ALB HTTPS listener (null if HTTPS disabled)."
  value       = length(local.private_alb_names) > 0 && var.private_albs[0].https_enabled ? module.private_alb[local.private_alb_names[0]].https_listener_arn : null
}

################################################################################
# Public NLBs
################################################################################

output "public_nlbs" {
  description = "All public NLBs with their attributes, in the same order as var.public_nlbs."
  value = [for name in local.public_nlb_names : {
    name              = name
    arn               = module.public_nlb[name].nlb_arn
    id                = module.public_nlb[name].nlb_id
    dns_name          = module.public_nlb[name].nlb_dns_name
    zone_id           = module.public_nlb[name].nlb_zone_id
    arn_suffix        = module.public_nlb[name].nlb_arn_suffix
    security_group_id = module.public_nlb[name].security_group_id
  }]
}

output "public_nlbs_by_name" {
  description = "Public NLB attributes keyed by load balancer name."
  value = { for name in local.public_nlb_names : name => {
    name              = name
    arn               = module.public_nlb[name].nlb_arn
    id                = module.public_nlb[name].nlb_id
    dns_name          = module.public_nlb[name].nlb_dns_name
    zone_id           = module.public_nlb[name].nlb_zone_id
    arn_suffix        = module.public_nlb[name].nlb_arn_suffix
    security_group_id = module.public_nlb[name].security_group_id
  } }
}

output "public_nlb_options" {
  description = "Public NLB select options ({label, value} pairs of load balancer names) for module definition forms."
  value       = [for name in local.public_nlb_names : { label = name, value = name }]
}

# Deprecated single-NLB outputs (first entry of public_nlbs); kept for
# consumers that support only one load balancer per type.

output "public_nlb_arn" {
  description = "The ARN of the first public NLB (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].nlb_arn : null
}

output "public_nlb_id" {
  description = "The ID of the first public NLB (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].nlb_id : null
}

output "public_nlb_dns_name" {
  description = "The DNS name of the first public NLB (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "The canonical hosted zone ID of the first public NLB (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "The ARN suffix of the first public NLB for CloudWatch Metrics (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].nlb_arn_suffix : null
}

output "public_nlb_security_group_id" {
  description = "The ID of the first public NLB security group (null if none)."
  value       = length(local.public_nlb_names) > 0 ? module.public_nlb[local.public_nlb_names[0]].security_group_id : null
}

################################################################################
# Private NLBs
################################################################################

output "private_nlbs" {
  description = "All private NLBs with their attributes, in the same order as var.private_nlbs."
  value = [for name in local.private_nlb_names : {
    name              = name
    arn               = module.private_nlb[name].nlb_arn
    id                = module.private_nlb[name].nlb_id
    dns_name          = module.private_nlb[name].nlb_dns_name
    zone_id           = module.private_nlb[name].nlb_zone_id
    arn_suffix        = module.private_nlb[name].nlb_arn_suffix
    security_group_id = module.private_nlb[name].security_group_id
  }]
}

output "private_nlbs_by_name" {
  description = "Private NLB attributes keyed by load balancer name."
  value = { for name in local.private_nlb_names : name => {
    name              = name
    arn               = module.private_nlb[name].nlb_arn
    id                = module.private_nlb[name].nlb_id
    dns_name          = module.private_nlb[name].nlb_dns_name
    zone_id           = module.private_nlb[name].nlb_zone_id
    arn_suffix        = module.private_nlb[name].nlb_arn_suffix
    security_group_id = module.private_nlb[name].security_group_id
  } }
}

output "private_nlb_options" {
  description = "Private NLB select options ({label, value} pairs of load balancer names) for module definition forms."
  value       = [for name in local.private_nlb_names : { label = name, value = name }]
}

# Deprecated single-NLB outputs (first entry of private_nlbs); kept for
# consumers that support only one load balancer per type.

output "private_nlb_arn" {
  description = "The ARN of the first private NLB (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].nlb_arn : null
}

output "private_nlb_id" {
  description = "The ID of the first private NLB (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].nlb_id : null
}

output "private_nlb_dns_name" {
  description = "The DNS name of the first private NLB (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "The canonical hosted zone ID of the first private NLB (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "The ARN suffix of the first private NLB for CloudWatch Metrics (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].nlb_arn_suffix : null
}

output "private_nlb_security_group_id" {
  description = "The ID of the first private NLB security group (null if none)."
  value       = length(local.private_nlb_names) > 0 ? module.private_nlb[local.private_nlb_names[0]].security_group_id : null
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
