module "placement" {
  source = "./modules/placement"

  public_subnets = [
    for id in var.public_subnet_ids : {
      id                = id
      availability_zone = data.aws_subnet.public[id].availability_zone
    }
  ]

  private_subnets = [
    for id in var.private_subnet_ids : {
      id                = id
      availability_zone = data.aws_subnet.private[id].availability_zone
      route_table_id    = local.private_subnet_route_table_ids[id]
    }
  ]

  high_availability_enabled = var.high_availability_enabled
}
