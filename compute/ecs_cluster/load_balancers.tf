################################################################################
# Public Application Load Balancer
################################################################################

module "public_alb" {
  count = var.public_alb_enabled ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-pub"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # Listener configuration. Keep listener ownership in the ALB module so
  # enabling managed domains changes only the default certificate in place.
  http_listener_enabled          = true
  https_listener_enabled         = var.public_alb_https_enabled
  http_to_https_redirect_enabled = var.public_alb_https_enabled

  # SSL/TLS
  # Managed mode makes the Ravion wildcard the DEFAULT certificate and keeps
  # every BYO certificate attached via SNI (the submodule attaches arns[1..]
  # as aws_lb_listener_certificate). Toggling managed domains on therefore
  # never drops TLS for hostnames served off existing BYO certificates.
  certificate_arns = local.enable_ravion_domain ? concat([ravion_aws_acm_certificate.cluster[0].arn], var.public_alb_certificate_arns) : var.public_alb_certificate_arns
  ssl_policy       = var.public_alb_ssl_policy

  # ALB settings
  idle_timeout                = var.public_alb_idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks      = var.public_alb_ingress_cidr_blocks
  ingress_ipv6_cidr_blocks = var.public_alb_ingress_ipv6_cidr_blocks

  # Access logs
  access_logs_enabled    = var.public_alb_access_logs_enabled
  access_logs_bucket_arn = var.public_alb_access_logs_bucket_arn

  # WAF
  web_acl_arn = var.public_alb_web_acl_arn
}

################################################################################
# Private Application Load Balancer
################################################################################

module "private_alb" {
  count = var.private_alb_enabled ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-priv"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
  internal_load_balancer_enabled = true

  # Listener configuration. Keep listener ownership in the ALB module so
  # enabling managed domains changes only the default certificate in place.
  http_listener_enabled          = true
  https_listener_enabled         = var.private_alb_https_enabled
  http_to_https_redirect_enabled = var.private_alb_https_enabled

  # SSL/TLS
  # Managed mode makes the Ravion wildcard the DEFAULT certificate and keeps
  # every BYO certificate attached via SNI (the submodule attaches arns[1..]
  # as aws_lb_listener_certificate). Toggling managed domains on therefore
  # never drops TLS for hostnames served off existing BYO certificates.
  certificate_arns = local.enable_ravion_domain ? concat([ravion_aws_acm_certificate.cluster[0].arn], var.private_alb_certificate_arns) : var.private_alb_certificate_arns
  ssl_policy       = var.private_alb_ssl_policy

  # ALB settings
  idle_timeout                = var.private_alb_idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks      = var.private_alb_ingress_cidr_blocks
  ingress_ipv6_cidr_blocks = var.private_alb_ingress_ipv6_cidr_blocks

  # Access logs
  access_logs_enabled    = var.private_alb_access_logs_enabled
  access_logs_bucket_arn = var.private_alb_access_logs_bucket_arn
}

################################################################################
# Public Network Load Balancer
################################################################################

module "public_nlb" {
  count = var.public_nlb_enabled ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-pub-nlb"
  tags   = var.tags
  vpc_id = var.vpc_id

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

################################################################################
# Private Network Load Balancer
################################################################################

module "private_nlb" {
  count = var.private_nlb_enabled ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-priv-nlb"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
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
