################################################################################
# IPv6 Egress-Only Internet Gateway
################################################################################

resource "aws_egress_only_internet_gateway" "this" {
  count = var.ipv6_enabled ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-eigw"
  })
}

resource "aws_route" "private_ipv6_egress" {
  count = var.ipv6_enabled ? local.private_route_table_count : 0

  route_table_id              = aws_route_table.private[count.index].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id
}
