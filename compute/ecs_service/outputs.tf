################################################################################
# ECS Service
################################################################################

output "service_id" {
  description = "The ID of the ECS service."
  value       = aws_ecs_service.this.id
}

output "service_arn" {
  description = "The ARN of the ECS service."
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "The name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "service_cluster" {
  description = "The cluster ARN where the service is running."
  value       = aws_ecs_service.this.cluster
}

output "cluster_name" {
  description = "The name of the ECS cluster where the service is running."
  value       = split("/", var.cluster_arn)[1]
}

################################################################################
# Task Definition
################################################################################

output "task_definition_arn" {
  description = "The ARN of the task definition."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "The family of the task definition."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "The revision of the task definition."
  value       = aws_ecs_task_definition.this.revision
}

################################################################################
# IAM Roles
################################################################################

output "execution_role_arn" {
  description = "The ARN of the task execution role."
  value       = local.create_execution_role ? aws_iam_role.execution[0].arn : var.execution_role_arn
}

output "execution_role_name" {
  description = "The name of the task execution role (null if using external role)."
  value       = local.create_execution_role ? aws_iam_role.execution[0].name : null
}

output "task_role_arn" {
  description = "The ARN of the task role."
  value       = local.create_task_role ? aws_iam_role.task[0].arn : var.task_role_arn
}

output "task_role_name" {
  description = "The name of the task role (null if using external role)."
  value       = local.create_task_role ? aws_iam_role.task[0].name : null
}

################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the ECS service security group."
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the ECS service security group."
  value       = module.security_group.security_group_arn
}

################################################################################
# Target Groups
#
# A production (tg-1) + alternate (tg-2) pair exists for attachments that
# support traffic shifting. Rolling-only multi-listener NLB attachments
# create one production target group per listener and no alternate.
################################################################################

output "target_group_arn" {
  description = "The ARN of the production target group the service serves from (alias of production_target_group_arn; null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn : null
}

output "target_group_arn_suffix" {
  description = "The ARN suffix of the production target group for CloudWatch metrics."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn_suffix : null
}

output "target_group_name" {
  description = "The name of the production target group the service serves from (alias of production_target_group_name; null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].name : null
}

output "production_target_group_arn" {
  description = "The ARN of the production target group (null if load balancer disabled)."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].arn : null
}

output "production_target_group_name" {
  description = "The name of the production target group."
  value       = local.enable_load_balancer ? aws_lb_target_group.tg_1[0].name : null
}

output "alternate_target_group_arn" {
  description = "The ARN of the alternate target group ECS shifts traffic to during native traffic-shift deployments (null if load balancer disabled)."
  value       = local.traffic_shift_infrastructure_enabled ? aws_lb_target_group.tg_2[0].arn : null
}

output "alternate_target_group_name" {
  description = "The name of the alternate target group."
  value       = local.traffic_shift_infrastructure_enabled ? aws_lb_target_group.tg_2[0].name : null
}

output "target_group_arns" {
  description = "Map of all target group ARNs created by this module."
  value = local.enable_load_balancer ? merge(
    {
      production = aws_lb_target_group.tg_1[0].arn
    },
    local.traffic_shift_infrastructure_enabled ? { alternate = aws_lb_target_group.tg_2[0].arn } : {},
    { for port, target_group in aws_lb_target_group.nlb_additional : "listener-${port}" => target_group.arn },
  ) : {}
}

################################################################################
# ECS Infrastructure Role
################################################################################

output "ecs_infrastructure_role_arn" {
  description = "The ARN of the IAM role ECS assumes to manage load-balancer wiring during native traffic-shift deployments (null if load balancer disabled)."
  value       = local.traffic_shift_infrastructure_enabled ? aws_iam_role.ecs_infrastructure[0].arn : null
}

################################################################################
# Listeners
################################################################################

output "listener_arns" {
  description = "ARNs of the ALB listeners the service is attached to (empty if no load balancer or NLB)."
  value       = local.enable_load_balancer ? [for rule in var.load_balancer_attachment.listener_rules : rule.listener_arn] : []
}

output "nlb_listener_arn" {
  description = "The ARN of the primary NLB listener created by this module (null if not using NLB)."
  value       = local.enable_nlb_listener ? aws_lb_listener.nlb[0].arn : null
}

output "nlb_listener_arns" {
  description = "Map of NLB listener ports to listener ARNs created by this module."
  value = local.enable_nlb_listener ? merge(
    { tostring(local.primary_nlb_listener.port) = aws_lb_listener.nlb[0].arn },
    { for port, listener in aws_lb_listener.nlb_additional : port => listener.arn },
  ) : {}
}

output "nlb_target_group_arns" {
  description = "Map of NLB listener ports to production target group ARNs."
  value = local.enable_nlb_listener ? merge(
    { tostring(local.primary_nlb_listener.port) = aws_lb_target_group.tg_1[0].arn },
    { for port, target_group in aws_lb_target_group.nlb_additional : port => target_group.arn },
  ) : {}
}

output "production_listener_rule_arn" {
  description = "ARN of the production ALB listener rule or primary NLB listener. The ECS deployment controller rewrites this value only for ALB traffic-shift deployments (null if load balancer disabled). For a Ravion-managed service this is the first module-created host-header rule on the cluster HTTPS listener."
  # The ravion rules are absent when the cluster has no HTTPS listener to put
  # them on; degrade to null rather than an "Invalid index" that would bury the
  # actionable cluster_https_listener_arn precondition on aws_ecs_service.
  value = local.enable_load_balancer ? (
    local.enable_nlb_listener ? aws_lb_listener.nlb[0].arn : (
      local.ravion_managed
      ? (length(aws_lb_listener_rule.ravion) > 0 ? aws_lb_listener_rule.ravion["0"].arn : null)
      : aws_lb_listener_rule.alb["0"].arn
    )
  ) : null
}

output "test_listener_rule_arn" {
  description = "ARN of the test listener rule the ECS deployment controller rewrites during the TEST_TRAFFIC_SHIFT lifecycle stages, routing test traffic to the green revision before the production cutover. The deploy manager passes it as advanced_configuration.test_listener_rule on UpdateService. Null when no module-created or externally-managed test listener rule is configured."
  value       = local.test_listener_rule_arn
}

################################################################################
# Load Balancer
################################################################################

output "load_balancer_arn" {
  description = "The ARN of the load balancer the service is attached to (null if no load balancer attachment)."
  value       = length(data.aws_lb.attached) > 0 ? data.aws_lb.attached[0].arn : null
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer the service is attached to. Useful as a CloudFront or DNS origin (null if no load balancer attachment)."
  value       = length(data.aws_lb.attached) > 0 ? data.aws_lb.attached[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "The canonical hosted zone ID of the load balancer the service is attached to, for Route53 alias records (null if no load balancer attachment)."
  value       = length(data.aws_lb.attached) > 0 ? data.aws_lb.attached[0].zone_id : null
}

################################################################################
# Auto Scaling
################################################################################

output "autoscaling_target_arn" {
  description = "The ARN of the Application Auto Scaling target (null if auto scaling disabled)."
  value       = local.auto_scaling_enabled ? aws_appautoscaling_target.this[0].id : null
}

output "autoscaling_policies" {
  description = "Map of auto scaling policy ARNs."
  value = local.auto_scaling_enabled ? {
    for name, policy in aws_appautoscaling_policy.target_tracking : name => policy.arn
  } : {}
}

################################################################################
# Service Discovery
################################################################################

output "service_discovery_arn" {
  description = "The ARN of the Cloud Map service (null if service discovery disabled)."
  value       = local.enable_service_discovery ? aws_service_discovery_service.this[0].arn : null
}

output "service_discovery_id" {
  description = "The ID of the Cloud Map service (null if service discovery disabled)."
  value       = local.enable_service_discovery ? aws_service_discovery_service.this[0].id : null
}

################################################################################
# Container Information
################################################################################

output "container_name" {
  description = "The name of the primary container."
  value       = local.lb_container_name
}

output "container_port" {
  description = "The port of the primary container (dummy value of 3000 if load balancer disabled)."
  value       = local.enable_load_balancer ? local.primary_load_balancer_container_port : 3000
}

################################################################################
# CloudWatch Logs
################################################################################

output "log_group_name" {
  description = "The name of the CloudWatch log group used by the task."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "The ARN of the CloudWatch log group used by the task."
  value       = aws_cloudwatch_log_group.this.arn
}

output "log_stream_prefix" {
  description = "The awslogs stream prefix for the primary container."
  value       = local.placeholder_container_name
}

################################################################################
# ECR
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

output "ravion_domain_fqdn" {
  description = "Primary FQDN for this service (first entry in the domains list; the auto-FQDN under the cluster wildcard when present). Null when the cluster has no Ravion-managed domains."
  value       = length(local.effective_domains) > 0 ? local.effective_domains[0] : null
}

output "ravion_domain_url" {
  description = "https URL for the primary FQDN."
  value       = length(local.effective_domains) > 0 ? "https://${local.effective_domains[0]}" : null
}

output "ravion_custom_cert_arn" {
  description = "ACM ARN of the per-service instance cert covering the custom (non-wildcard) domains. Null when there are none."
  value       = length(local.custom_domains) > 0 ? ravion_aws_acm_certificate.svc[0].arn : null
}
