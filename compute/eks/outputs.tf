################################################################################
# Cluster
################################################################################

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.cluster.cluster_name
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = module.cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "The Kubernetes API server endpoint URL."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the Kubernetes API server. Use this in kubeconfig."
  value       = module.cluster.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster."
  value       = module.cluster.cluster_version
}

output "region" {
  description = "The AWS region where the cluster is deployed."
  value       = module.cluster.region
}

output "aws_account_id" {
  description = "The AWS account ID where the cluster is deployed."
  value       = module.cluster.aws_account_id
}

################################################################################
# Identity / Networking
################################################################################

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (for IRSA trust policies)."
  value       = module.cluster.oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider for IRSA (null when creation is disabled)."
  value       = module.cluster.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = module.cluster.cluster_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC the cluster runs in. Consumed by workload modules that create load balancer target groups, which must live in the same VPC as the pods they register."
  value       = var.vpc_id
}

output "node_subnet_ids" {
  description = "Subnet IDs used for node placement (node_subnet_ids, falling back to subnet_ids). Consumed by compute/eks/addons for the default Karpenter NodePool."
  value       = local.node_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs passed through for dependent modules (compute/eks/addons shared load balancers). Empty when not provided."
  value       = var.public_subnet_ids
}

output "ravion_runner_role_arn" {
  description = "ARN of the IAM role Ravion Runner step executions assume for Kubernetes API access (null when disabled)."
  value       = var.ravion_runner_role_creation_enabled ? module.ravion_runner_role[0].role_arn : null
}

output "ravion_runner_security_group_id" {
  description = "ID of the Ravion Runner security group allowed to reach the cluster API endpoint (null if disabled)."
  value       = var.ravion_runner_security_group_creation_enabled ? aws_security_group.ravion_runner[0].id : null
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for Kubernetes secrets envelope encryption (null if disabled)."
  value       = module.cluster.secrets_kms_key_arn
}

output "lb_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller Pod Identity role (null if disabled)."
  value       = module.cluster.lb_controller_role_arn
}

output "topology_aware_routing_enabled" {
  description = "Whether this cluster keeps Service traffic zone-local by default. Consumed by compute/eks/addons as the default for patching the kube-dns Service with trafficDistribution: PreferClose."
  value       = var.topology_aware_routing_enabled
}

################################################################################
# Node Groups
################################################################################

output "system_node_group_name" {
  description = "Name of the system managed node group."
  value       = module.system_node_group.node_group_name
}

output "system_node_group_arn" {
  description = "ARN of the system managed node group."
  value       = module.system_node_group.node_group_arn
}

output "additional_node_group_names" {
  description = "Map of additional node group key -> node group name."
  value       = { for k, m in module.node_groups : k => m.node_group_name }
}

################################################################################
# Fargate
################################################################################

output "fargate_profile_names" {
  description = "Map of Fargate profile key -> profile name."
  value       = { for k, m in module.fargate_profiles : k => m.fargate_profile_name }
}
