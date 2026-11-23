################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# With nat_instance_route_takeover_enabled, read each private route table's
# live default route so a NAT instance (for example alterNAT) that has taken it
# over keeps it across deploys. Reading the target, rather than ignoring
# changes to it, keeps the route at the same address (no state migration, no
# destroy) and still repoints a route left on a replaced NAT gateway.
data "aws_route_table" "private_nat_live" {
  count = var.nat_instance_route_takeover_enabled ? local.nat_gateway_count : 0

  route_table_id = aws_route_table.private[count.index].id
}
