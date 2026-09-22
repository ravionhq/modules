locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/vpc"
  }
  tags = merge(local.default_tags, var.tags)

  # Availability Zones
  selected_availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available.names
  automatic_subnet_count      = min(3, length(local.selected_availability_zones))
  subnet_count                = var.subnet_count != null ? var.subnet_count : local.automatic_subnet_count
  azs                         = slice(local.selected_availability_zones, 0, min(local.subnet_count, length(local.selected_availability_zones)))

  # Subnet CIDRs - auto-calculate if not provided
  # Public subnets: /24 blocks at offset 1, 2, 3, ... (e.g., 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
  # Private subnets: /24 blocks at offset 11, 12, 13, ... (e.g., 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24)
  automatic_public_subnet_cidrs = [
    for i in range(local.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]
  automatic_private_subnet_cidrs = [
    for i in range(local.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 11)
  ]
  public_subnet_cidrs  = var.public_subnet_cidrs != null && length(var.public_subnet_cidrs) == local.subnet_count ? var.public_subnet_cidrs : local.automatic_public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs != null && length(var.private_subnet_cidrs) == local.subnet_count ? var.private_subnet_cidrs : local.automatic_private_subnet_cidrs

  # NAT Gateway HA mode (with deprecated single_nat_gateway override)
  nat_gateway_high_availability_enabled = var.single_nat_gateway != null ? !var.single_nat_gateway : var.nat_gateway_high_availability_enabled

  # NAT Gateway count
  nat_gateway_count = var.nat_gateway_enabled ? (local.nat_gateway_high_availability_enabled ? local.subnet_count : 1) : 0

  # NAT Gateway EIPs
  # When the caller supplies pre-allocated EIPs, skip creating internal ones and
  # use the supplied allocation IDs directly. Otherwise, fall back to the EIPs
  # created by aws_eip.nat in this module. An empty list is treated the same as
  # null (auto-allocate), since callers that template tfvars often can't omit
  # the key.
  supplied_nat_eip_allocation_ids = (
    var.nat_gateway_eip_allocation_ids != null && length(var.nat_gateway_eip_allocation_ids) > 0
    ? var.nat_gateway_eip_allocation_ids
    : null
  )
  supplied_nat_eip_allocation_ids_match_count = local.supplied_nat_eip_allocation_ids == null || length(local.supplied_nat_eip_allocation_ids) == local.nat_gateway_count
  create_nat_eips                             = var.nat_gateway_enabled && local.supplied_nat_eip_allocation_ids == null
  nat_gateway_eip_allocation_ids              = local.supplied_nat_eip_allocation_ids != null && local.supplied_nat_eip_allocation_ids_match_count ? local.supplied_nat_eip_allocation_ids : aws_eip.nat[*].allocation_id

  # VPC Endpoints
  # Callers that template tfvars often can't omit the key, so treat null the
  # same as an empty list (no interface endpoints).
  vpc_endpoint_interface_services = var.vpc_endpoint_interface_services != null ? var.vpc_endpoint_interface_services : []

  # Flow Logs
  create_flow_log_cloudwatch = var.flow_logs_enabled && var.flow_logs_destination == "cloudwatch"
  create_flow_log_s3         = var.flow_logs_enabled && var.flow_logs_destination == "s3"
  create_flow_log_s3_bucket  = local.create_flow_log_s3 && var.flow_logs_s3_bucket_arn == null
  flow_log_s3_bucket_arn     = local.create_flow_log_s3_bucket ? aws_s3_bucket.flow_logs[0].arn : var.flow_logs_s3_bucket_arn
}
