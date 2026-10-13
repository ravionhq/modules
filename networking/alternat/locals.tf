locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/alternat"
  }
  tags = merge(local.default_tags, var.tags)

  vpc_ipv4_cidr_blocks = [for association in data.aws_vpc.this.cidr_block_associations : association.cidr_block]
  vpc_ipv6_cidr_blocks = [for association in data.aws_vpc.this.ipv6_cidr_block_associations : association.ipv6_cidr_block]

  architecture = contains(data.aws_ec2_instance_type.nat.supported_architectures, "arm64") ? "arm64" : "x86_64"

  ################################################################################
  # Route tables and NAT instance placement
  ################################################################################

  # Private subnets with no explicit route table association use the VPC's
  # main route table.
  private_subnet_route_table_ids = {
    for id in var.private_subnet_ids : id => (
      length(data.aws_route_tables.private_subnet[id].ids) > 0
      ? data.aws_route_tables.private_subnet[id].ids[0]
      : data.aws_route_table.main.id
    )
  }

  public_subnet_route_table_ids = distinct([
    for id in var.public_subnet_ids : (
      length(data.aws_route_tables.public_subnet[id].ids) > 0
      ? data.aws_route_tables.public_subnet[id].ids[0]
      : data.aws_route_table.main.id
    )
  ])

  # Route tables both public and private subnets use. alterNAT replacing their
  # 0.0.0.0/0 route would cut the NAT instances off from the internet.
  shared_route_table_ids = setintersection(toset(local.public_subnet_route_table_ids), toset(values(local.private_subnet_route_table_ids)))

  route_table_ids    = module.placement.route_table_ids
  route_table_nat_az = module.placement.route_table_nat_az
  nat_azs            = module.placement.nat_azs
  vpc_az_maps        = module.placement.vpc_az_maps

  ################################################################################
  # Fallback NAT gateway
  ################################################################################

  available_nat_gateway_ids = var.fallback_nat_gateway_mode == "existing" ? data.aws_nat_gateways.existing[0].ids : []

  # Selection among the existing NAT gateways lives in modules/fallback.
  existing_nat_gateway_ids = module.fallback.public_nat_gateway_ids
  fallback_nat_gateway_id  = var.fallback_nat_gateway_mode == "existing" ? module.fallback.fallback_nat_gateway_id : ""

  ################################################################################
  # Resource names
  ################################################################################

  connectivity_tester_function_name = "${var.name}-connectivity-tester"
  autoscaling_hook_function_name    = "${var.name}-autoscaling-hook"
}
