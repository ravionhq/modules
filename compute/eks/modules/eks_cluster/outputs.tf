################################################################################
# Cluster
################################################################################

output "cluster_id" {
  description = "The ID (name) of the EKS cluster."
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "The Kubernetes API server endpoint URL."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the Kubernetes API server. Use this in kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "The platform version of the cluster (AWS-internal versioning of EKS itself)."
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster (ACTIVE, CREATING, DELETING, FAILED, UPDATING)."
  value       = aws_eks_cluster.this.status
}

################################################################################
# Networking
################################################################################

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group used for control-plane <-> node communication."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_vpc_config" {
  description = "The VPC configuration of the cluster."
  value       = aws_eks_cluster.this.vpc_config[0]
}

################################################################################
# IAM / Identity
################################################################################

output "cluster_iam_role_arn" {
  description = "ARN of the IAM service role used by the EKS control plane."
  value       = module.cluster_role.role_arn
}

output "cluster_iam_role_name" {
  description = "Name of the IAM service role used by the EKS control plane."
  value       = module.cluster_role.role_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (https://oidc.eks.<region>.amazonaws.com/id/<id>). Use for IRSA trust policies."
  value       = local.oidc_issuer
}

output "oidc_issuer_host" {
  description = "OIDC issuer hostname without scheme (oidc.eks.<region>.amazonaws.com/id/<id>). Use as the variable prefix in IRSA conditions."
  value       = local.oidc_issuer_host
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider for IRSA (null when creation is disabled)."
  value       = one(aws_iam_openid_connect_provider.this[*].arn)
}

################################################################################
# Encryption / Logging
################################################################################

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for Kubernetes secrets envelope encryption (null if disabled)."
  value       = local.secrets_kms_key_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the EKS control plane CloudWatch log group (null if logging disabled)."
  value       = local.enable_logging ? aws_cloudwatch_log_group.cluster[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the EKS control plane CloudWatch log group (null if logging disabled)."
  value       = local.enable_logging ? aws_cloudwatch_log_group.cluster[0].arn : null
}

################################################################################
# Helper Roles
################################################################################

output "lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller Pod Identity role (null if disabled)."
  value       = var.aws_load_balancer_controller_pod_identity_creation_enabled ? module.lb_controller_role[0].role_arn : null
}

output "lb_controller_role_name" {
  description = "Name of the AWS Load Balancer Controller Pod Identity role (null if disabled)."
  value       = var.aws_load_balancer_controller_pod_identity_creation_enabled ? module.lb_controller_role[0].role_name : null
}

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the cluster is deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the cluster is deployed."
  value       = local.region
}
