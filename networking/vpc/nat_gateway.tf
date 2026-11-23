################################################################################
# NAT Gateway
################################################################################

resource "aws_eip" "nat" {
  count = local.create_nat_eips ? local.nat_gateway_count : 0

  domain = "vpc"

  tags = merge(local.tags, {
    Name = local.nat_gateway_high_availability_enabled ? "${var.name}-nat-${local.azs[count.index]}" : "${var.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = local.nat_gateway_eip_allocation_ids[count.index]
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = local.nat_gateway_high_availability_enabled ? "${var.name}-nat-${local.azs[count.index]}" : "${var.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.private_nat_route_instance_targets[count.index] == null ? aws_nat_gateway.this[count.index].id : null
  network_interface_id   = local.private_nat_route_instance_targets[count.index]
}
