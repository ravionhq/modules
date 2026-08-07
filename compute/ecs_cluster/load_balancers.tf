################################################################################
# Public Application Load Balancers
################################################################################

module "public_alb" {
  for_each = local.public_albs_by_name

  source = "../../networking/alb"

  name   = each.key
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = each.value.https_enabled
  http_to_https_redirect_enabled = each.value.https_enabled

  # SSL/TLS
  certificate_arns = each.value.certificate_arns
  ssl_policy       = each.value.ssl_policy

  # ALB settings
  idle_timeout                = each.value.idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = each.value.ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = each.value.ingress_ipv6_cidr_blocks
  ingress_security_group_ids = each.value.ingress_security_group_ids

  # Access logs
  access_logs_enabled    = each.value.access_logs_enabled
  access_logs_bucket_arn = each.value.access_logs_bucket_arn

  # WAF
  web_acl_arn = each.value.web_acl_arn
}

################################################################################
# Private Application Load Balancers
################################################################################

module "private_alb" {
  for_each = local.private_albs_by_name

  source = "../../networking/alb"

  name   = each.key
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
  internal_load_balancer_enabled = true

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = each.value.https_enabled
  http_to_https_redirect_enabled = each.value.https_enabled

  # SSL/TLS
  certificate_arns = each.value.certificate_arns
  ssl_policy       = each.value.ssl_policy

  # ALB settings
  idle_timeout                = each.value.idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = each.value.ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = each.value.ingress_ipv6_cidr_blocks
  ingress_security_group_ids = each.value.ingress_security_group_ids

  # Access logs
  access_logs_enabled    = each.value.access_logs_enabled
  access_logs_bucket_arn = each.value.access_logs_bucket_arn
}

################################################################################
# Public Network Load Balancers
################################################################################

module "public_nlb" {
  for_each = local.public_nlbs_by_name

  source = "../../networking/nlb"

  name   = each.key
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = each.value.cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = each.value.security_group_ids

  # Access logs
  access_logs_enabled    = each.value.access_logs_enabled
  access_logs_bucket_arn = each.value.access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = each.value.elastic_ips_enabled
  elastic_ip_allocation_ids = each.value.elastic_ip_allocation_ids
}

################################################################################
# Private Network Load Balancers
################################################################################

module "private_nlb" {
  for_each = local.private_nlbs_by_name

  source = "../../networking/nlb"

  name   = each.key
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
  internal_load_balancer_enabled = true

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = each.value.cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = each.value.security_group_ids

  # Access logs
  access_logs_enabled    = each.value.access_logs_enabled
  access_logs_bucket_arn = each.value.access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = each.value.elastic_ips_enabled
  elastic_ip_allocation_ids = each.value.elastic_ip_allocation_ids
}
