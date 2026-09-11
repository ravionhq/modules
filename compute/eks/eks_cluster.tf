################################################################################
# EKS Cluster
################################################################################

module "cluster" {
  source = "./modules/eks_cluster"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access_enabled  = var.endpoint_public_access_enabled
  endpoint_private_access_enabled = var.endpoint_private_access_enabled
  public_access_cidrs             = var.public_access_cidrs
  service_ipv4_cidr               = var.service_ipv4_cidr
  ip_family                       = var.ip_family

  cluster_security_group_additional_cidr_ingress_rules                      = var.cluster_security_group_additional_cidr_ingress_rules
  cluster_security_group_additional_referenced_security_group_ingress_rules = var.cluster_security_group_additional_referenced_security_group_ingress_rules

  bootstrap_cluster_creator_admin_permissions_enabled = var.bootstrap_cluster_creator_admin_permissions_enabled
  access_entries                                      = var.access_entries

  oidc_provider_creation_enabled         = var.oidc_provider_creation_enabled
  vpc_resource_controller_policy_enabled = var.vpc_resource_controller_policy_enabled

  enabled_cluster_log_types     = var.enabled_cluster_log_types
  cluster_log_retention_in_days = var.cluster_log_retention_in_days

  secrets_encryption_enabled = var.secrets_encryption_enabled
  secrets_kms_key_arn        = var.secrets_kms_key_arn

  vpc_cni_addon_version                 = var.vpc_cni_addon_version
  vpc_cni_addon_configuration_values    = var.vpc_cni_addon_configuration_values
  kube_proxy_addon_version              = var.kube_proxy_addon_version
  kube_proxy_addon_configuration_values = var.kube_proxy_addon_configuration_values

  pod_identity_agent_enabled       = var.pod_identity_agent_enabled
  pod_identity_agent_addon_version = var.pod_identity_agent_addon_version

  aws_load_balancer_controller_pod_identity_creation_enabled = var.aws_load_balancer_controller_pod_identity_creation_enabled
  aws_load_balancer_controller_namespace                     = var.aws_load_balancer_controller_namespace
  aws_load_balancer_controller_service_account               = var.aws_load_balancer_controller_service_account

  pod_identity_associations = var.pod_identity_associations

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = local.tags
}
