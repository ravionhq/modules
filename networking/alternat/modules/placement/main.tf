# Decides how many NAT instances run, where, and which private route tables
# each serves. Pure computation, so it is testable without AWS.

locals {
  route_table_ids = sort(distinct([for subnet in var.private_subnets : subnet.route_table_id]))

  # Availability zones of the private subnets each route table serves.
  route_table_azs = {
    for route_table_id in local.route_table_ids : route_table_id => sort(distinct([
      for subnet in var.private_subnets : subnet.availability_zone if subnet.route_table_id == route_table_id
    ]))
  }

  # First public subnet, in input order, of each availability zone.
  public_subnet_id_by_az = {
    for az in distinct([for subnet in var.public_subnets : subnet.availability_zone]) :
    az => [for subnet in var.public_subnets : subnet.id if subnet.availability_zone == az][0]
  }
  public_azs = keys(local.public_subnet_id_by_az)

  # Without high availability, the one NAT instance runs in the first private
  # availability zone that has a public subnet.
  single_nat_az = try(
    [
      for az in flatten([for route_table_id in local.route_table_ids : local.route_table_azs[route_table_id]]) :
      az if contains(local.public_azs, az)
    ][0],
    var.public_subnets[0].availability_zone,
  )

  # Each route table is served by a NAT instance in an availability zone it
  # serves, so its traffic stays in-zone. A route table shared across zones
  # (one private route table for the whole VPC) gets a single NAT instance.
  route_table_nat_az = {
    for route_table_id, azs in local.route_table_azs : route_table_id => (
      var.high_availability_enabled
      ? try([for az in azs : az if contains(local.public_azs, az)][0], local.single_nat_az)
      : local.single_nat_az
    )
  }

  nat_azs = sort(distinct(values(local.route_table_nat_az)))

  vpc_az_maps = [
    for az in local.nat_azs : {
      az               = az
      public_subnet_id = local.public_subnet_id_by_az[az]
      route_table_ids  = [for route_table_id, nat_az in local.route_table_nat_az : route_table_id if nat_az == az]
      # The connectivity tester runs in the private subnets this NAT instance
      # serves, so it tests the same path their traffic takes.
      private_subnet_ids = [
        for subnet in var.private_subnets : subnet.id if local.route_table_nat_az[subnet.route_table_id] == az
      ]
    }
  ]

  # One private subnet per availability zone, for interface endpoints.
  endpoint_subnet_ids = [
    for az in sort(distinct([for subnet in var.private_subnets : subnet.availability_zone])) :
    [for subnet in var.private_subnets : subnet.id if subnet.availability_zone == az][0]
  ]
}
