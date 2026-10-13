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
  # Only public NAT gateways can be a fallback: a private one has no route to
  # the internet.
  existing_nat_gateway_ids          = sort([for gateway in data.aws_nat_gateway.existing : gateway.id if gateway.connectivity_type == "public"])
  existing_nat_gateway_subnet_ids   = [for gateway in data.aws_nat_gateway.existing : gateway.subnet_id if gateway.connectivity_type == "public"]
  nat_azs_without_existing_gateways = [for az_map in local.vpc_az_maps : az_map.az if !contains(local.existing_nat_gateway_subnet_ids, az_map.public_subnet_id)]

  # An empty ID makes alterNAT fail over to the NAT gateway in the NAT
  # instance's own public subnet.
  fallback_nat_gateway_id = (
    var.fallback_nat_gateway_mode != "existing" ? "" :
    var.fallback_nat_gateway_id != null ? var.fallback_nat_gateway_id :
    length(local.existing_nat_gateway_ids) == 1 ? local.existing_nat_gateway_ids[0] :
    ""
  )

  ################################################################################
  # Resource names
  ################################################################################

  connectivity_tester_function_name = "${var.name}-connectivity-tester"
  autoscaling_hook_function_name    = "${var.name}-autoscaling-hook"
}
