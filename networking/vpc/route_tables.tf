################################################################################
# Public Route Table
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "public_internet_ipv6" {
  count = var.ipv6_enabled ? 1 : 0

  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.subnet_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Private Route Tables
################################################################################

# When using a single NAT gateway, we only need one private route table
# When using multiple NAT gateways (one per AZ), we need one route table per AZ
resource "aws_route_table" "private" {
  count = local.nat_gateway_high_availability_enabled ? local.subnet_count : 1

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = local.nat_gateway_high_availability_enabled ? "${var.name}-private-${local.azs[count.index]}" : "${var.name}-private"
  })
}

resource "aws_route_table_association" "private" {
  count = local.subnet_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = local.nat_gateway_high_availability_enabled ? aws_route_table.private[count.index].id : aws_route_table.private[0].id
}

################################################################################
# Private Subnet Group Route Tables
################################################################################

# Like the private route tables: one per AZ when NAT gateways are highly
# available, otherwise one per group.
resource "aws_route_table" "private_group" {
  for_each = local.private_subnet_group_route_tables

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name        = local.nat_gateway_high_availability_enabled ? "${var.name}-${each.value.group}-${local.azs[each.value.index]}" : "${var.name}-${each.value.group}"
    SubnetGroup = each.value.group
  })
}

resource "aws_route_table_association" "private_group" {
  for_each = local.private_subnet_group_subnets

  subnet_id      = aws_subnet.private_group[each.key].id
  route_table_id = aws_route_table.private_group[local.nat_gateway_high_availability_enabled ? each.key : "${each.value.group}-0"].id
}
