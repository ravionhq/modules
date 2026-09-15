################################################################################
# Shared Load Balancers
#
# Terraform-managed ALBs/NLBs that web workloads attach to via the AWS Load
# Balancer Controller's TargetGroupBinding CRD — the same shared-LB pattern the
# ECS Cluster module uses. Workload modules create their own target group and
# listener rule, then bind pods to the target group in-cluster.
#
# Each ingress rule below opens the EKS cluster security group to the load
# balancer's security group across all TCP ports, since pods can expose any
# container port.
################################################################################

locals {
  vpc_id = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

################################################################################
# Public Application Load Balancer
################################################################################

module "public_alb" {
  count = var.public_alb_creation_enabled ? 1 : 0

  source = "../../../networking/alb"

  name   = "${var.cluster_name}-pub"
  tags   = local.tags
  vpc_id = local.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = var.public_alb_https_enabled
  http_to_https_redirect_enabled = var.public_alb_https_enabled

  # SSL/TLS
  certificate_arns = var.public_alb_certificate_arns
  ssl_policy       = var.public_alb_ssl_policy

  # ALB settings
  idle_timeout                = var.public_alb_idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = var.public_alb_ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = var.public_alb_ingress_ipv6_cidr_blocks
  ingress_security_group_ids = var.public_alb_ingress_security_group_ids

  # Access logs
  access_logs_enabled    = var.public_alb_access_logs_enabled
  access_logs_bucket_arn = var.public_alb_access_logs_bucket_arn

  # WAF
  web_acl_arn = var.public_alb_web_acl_arn
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_public_alb" {
  count = var.public_alb_creation_enabled ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  description                  = "Public ALB to pods (${var.cluster_name})"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = module.public_alb[0].security_group_id

  tags = local.tags
}

################################################################################
# Private Application Load Balancer
################################################################################

module "private_alb" {
  count = var.private_alb_creation_enabled ? 1 : 0

  source = "../../../networking/alb"

  name   = "${var.cluster_name}-priv"
  tags   = local.tags
  vpc_id = local.vpc_id

  subnet_ids                     = var.node_subnet_ids
  internal_load_balancer_enabled = true

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = var.private_alb_https_enabled
  http_to_https_redirect_enabled = var.private_alb_https_enabled

  # SSL/TLS
  certificate_arns = var.private_alb_certificate_arns
  ssl_policy       = var.private_alb_ssl_policy

  # ALB settings
  idle_timeout                = var.private_alb_idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = var.private_alb_ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = var.private_alb_ingress_ipv6_cidr_blocks
  ingress_security_group_ids = var.private_alb_ingress_security_group_ids

  # Access logs
  access_logs_enabled    = var.private_alb_access_logs_enabled
  access_logs_bucket_arn = var.private_alb_access_logs_bucket_arn
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_private_alb" {
  count = var.private_alb_creation_enabled ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  description                  = "Private ALB to pods (${var.cluster_name})"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = module.private_alb[0].security_group_id

  tags = local.tags
}

################################################################################
# Public Network Load Balancer
################################################################################

module "public_nlb" {
  count = var.public_nlb_creation_enabled ? 1 : 0

  source = "../../../networking/nlb"

  name   = "${var.cluster_name}-pub-nlb"
  tags   = local.tags
  vpc_id = local.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = var.public_nlb_cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = var.public_nlb_security_group_ids

  # Access logs
  access_logs_enabled    = var.public_nlb_access_logs_enabled
  access_logs_bucket_arn = var.public_nlb_access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = var.public_nlb_elastic_ips_enabled
  elastic_ip_allocation_ids = var.public_nlb_elastic_ip_allocation_ids
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_public_nlb" {
  count = var.public_nlb_creation_enabled ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  description                  = "Public NLB to pods (${var.cluster_name})"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = module.public_nlb[0].security_group_id

  tags = local.tags
}

################################################################################
# Private Network Load Balancer
################################################################################

module "private_nlb" {
  count = var.private_nlb_creation_enabled ? 1 : 0

  source = "../../../networking/nlb"

  name   = "${var.cluster_name}-priv-nlb"
  tags   = local.tags
  vpc_id = local.vpc_id

  subnet_ids                     = var.node_subnet_ids
  internal_load_balancer_enabled = true

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = var.private_nlb_cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = var.private_nlb_security_group_ids

  # Access logs
  access_logs_enabled    = var.private_nlb_access_logs_enabled
  access_logs_bucket_arn = var.private_nlb_access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = var.private_nlb_elastic_ips_enabled
  elastic_ip_allocation_ids = var.private_nlb_elastic_ip_allocation_ids
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_private_nlb" {
  count = var.private_nlb_creation_enabled ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  description                  = "Private NLB to pods (${var.cluster_name})"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = module.private_nlb[0].security_group_id

  tags = local.tags
}
