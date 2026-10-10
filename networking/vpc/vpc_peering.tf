################################################################################
# VPC Peering Connections
################################################################################

resource "aws_vpc_peering_connection" "this" {
  for_each = var.vpc_peering_connections

  vpc_id        = aws_vpc.this.id
  peer_vpc_id   = each.value.peer_vpc_id
  peer_owner_id = each.value.peer_owner_id
  peer_region   = each.value.peer_region

  # auto_accept is only valid for same-account, same-region peerings.
  auto_accept = each.value.peer_owner_id == null && each.value.peer_region == null ? each.value.auto_accept : false

  tags = merge(local.tags, each.value.tags, {
    Name = "${var.name}-peering-${each.key}"
  })
}

# Options on the requester (this VPC). Only applies for same-account, same-region
# peerings that have been accepted.
resource "aws_vpc_peering_connection_options" "requester" {
  for_each = {
    for k, v in var.vpc_peering_connections : k => v
    if v.peer_owner_id == null && v.peer_region == null && v.auto_accept && v.remote_vpc_dns_resolution_enabled
  }

  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id

  requester {
    allow_remote_vpc_dns_resolution = each.value.remote_vpc_dns_resolution_enabled
  }
}

################################################################################
# Routes for VPC Peering
################################################################################

locals {
  # Flatten peering connections into per-CIDR routes for the public route table.
  vpc_peering_public_routes = merge([
    for k, v in var.vpc_peering_connections : {
      for cidr in v.peer_cidr_blocks : "${k}-${cidr}" => {
        peering_key      = k
        destination_cidr = cidr
      }
      if v.public_route_table_routes_enabled
    }
  ]...)

  # Cartesian product of (peering route x private route table) for the private route tables.
  # aws_route_table.private may be 1 or N depending on nat_gateway_high_availability_enabled.
  vpc_peering_private_routes = merge([
    for k, v in var.vpc_peering_connections : merge([
      for rt_idx in range(length(aws_route_table.private)) : {
        for cidr in v.peer_cidr_blocks : "${k}-${rt_idx}-${cidr}" => {
          peering_key      = k
          destination_cidr = cidr
          route_table_id   = aws_route_table.private[rt_idx].id
        }
      }
    ]...)
    if v.private_route_table_routes_enabled
  ]...)
}

# Private subnet groups take the same peering routes as the private route tables.
locals {
  vpc_peering_private_group_routes = merge([
    for k, v in var.vpc_peering_connections : merge([
      for table_key, table in local.private_subnet_group_route_tables : {
        for cidr in v.peer_cidr_blocks : "${k}-${table_key}-${cidr}" => {
          peering_key      = k
          destination_cidr = cidr
          route_table_key  = table_key
        }
      }
    ]...)
    if v.private_route_table_routes_enabled
  ]...)
}

resource "aws_route" "public_vpc_peering" {
  for_each = local.vpc_peering_public_routes

  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = each.value.destination_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.value.peering_key].id
}

resource "aws_route" "private_vpc_peering" {
  for_each = local.vpc_peering_private_routes

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = each.value.destination_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.value.peering_key].id
}

resource "aws_route" "private_group_vpc_peering" {
  for_each = local.vpc_peering_private_group_routes

  route_table_id            = aws_route_table.private_group[each.value.route_table_key].id
  destination_cidr_block    = each.value.destination_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.value.peering_key].id
}

################################################################################
# Return Routes on the Peer Side
################################################################################
#
# When peer_route_table_ids is set on a peering, add return routes (destination =
# this VPC's CIDR) on each of the specified peer route tables. This is only
# supported for same-account, same-region peerings since the AWS provider used by
# this module must have access to the peer's route tables.

locals {
  vpc_peering_peer_routes = merge([
    for k, v in var.vpc_peering_connections : {
      for rt_id in v.peer_route_table_ids : "${k}-${rt_id}" => {
        peering_key    = k
        route_table_id = rt_id
      }
    }
  ]...)
}

resource "aws_route" "peer_vpc_peering" {
  for_each = local.vpc_peering_peer_routes

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = aws_vpc.this.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.value.peering_key].id
}
