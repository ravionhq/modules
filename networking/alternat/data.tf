data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)

  id = each.key
}

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)

  id = each.key
}

# The route table explicitly associated with each private subnet. Discovery
# reads associations, not routes, so it is unaffected by alterNAT rewriting the
# 0.0.0.0/0 route.
data "aws_route_tables" "private_subnet" {
  for_each = toset(var.private_subnet_ids)

  vpc_id = var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = [each.key]
  }
}

# Used by private subnets that have no explicit route table association.
data "aws_route_table" "main" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

data "aws_ec2_instance_type" "nat" {
  instance_type = var.nat_instance_type
}

data "aws_nat_gateways" "existing" {
  count = var.fallback_nat_gateway_mode == "existing" ? 1 : 0

  vpc_id = var.vpc_id

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_nat_gateway" "existing" {
  for_each = toset(local.existing_nat_gateway_ids)

  id = each.key
}

data "aws_eip" "nat_instance" {
  for_each = toset(var.nat_instance_eip_allocation_ids)

  id = each.key
}
