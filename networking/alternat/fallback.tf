module "fallback" {
  source = "./modules/fallback"

  nat_gateways = [
    for gateway in data.aws_nat_gateway.existing : {
      id                = gateway.id
      subnet_id         = gateway.subnet_id
      connectivity_type = gateway.connectivity_type
    }
  ]

  nat_instances = [
    for az_map in local.vpc_az_maps : {
      availability_zone = az_map.az
      public_subnet_id  = az_map.public_subnet_id
    }
  ]

  fallback_nat_gateway_id = var.fallback_nat_gateway_id
}
