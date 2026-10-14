# Chooses the existing NAT gateway each alterNAT instance fails over to. Pure
# computation, so it is testable without AWS.

locals {
  # Only public NAT gateways can be a fallback: a private one has no route to
  # the internet.
  public_nat_gateways    = [for gateway in var.nat_gateways : gateway if gateway.connectivity_type == "public"]
  public_nat_gateway_ids = sort([for gateway in local.public_nat_gateways : gateway.id])

  nat_instance_subnet_ids = [for instance in var.nat_instances : instance.public_subnet_id]

  # alterNAT instances whose public subnet has no public NAT gateway, which
  # matters when alterNAT has to pick the gateway in each instance's subnet.
  nat_azs_without_public_gateway = [
    for instance in var.nat_instances : instance.availability_zone
    if !contains([for gateway in local.public_nat_gateways : gateway.subnet_id], instance.public_subnet_id)
  ]

  # An empty ID makes alterNAT fail over to the NAT gateway in the alterNAT
  # instance's own public subnet.
  fallback_nat_gateway_id = (
    var.fallback_nat_gateway_id != null ? var.fallback_nat_gateway_id :
    length(local.public_nat_gateway_ids) == 1 ? local.public_nat_gateway_ids[0] :
    ""
  )

  fallback_nat_gateway_ids = (
    local.fallback_nat_gateway_id != "" ? [local.fallback_nat_gateway_id] :
    sort(distinct([for gateway in local.public_nat_gateways : gateway.id if contains(local.nat_instance_subnet_ids, gateway.subnet_id)]))
  )

  # Every alterNAT instance has a public NAT gateway to fail over to.
  valid = (
    var.fallback_nat_gateway_id != null ||
    length(local.public_nat_gateway_ids) == 1 ||
    (length(local.public_nat_gateway_ids) > 1 && length(local.nat_azs_without_public_gateway) == 0)
  )

  error_message = (
    length(local.public_nat_gateway_ids) == 0
    ? "no available public NAT gateway to fail over to. Set fallback_nat_gateway_mode to create, or create a NAT gateway first."
    : "several public NAT gateways, and none is in the public subnet of the alterNAT instance(s) in ${join(", ", local.nat_azs_without_public_gateway)}. Set fallback_nat_gateway_id to choose one."
  )
}
