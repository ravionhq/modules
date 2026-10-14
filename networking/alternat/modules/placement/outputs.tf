output "route_table_ids" {
  description = "Private route tables the NAT instances serve."
  value       = local.route_table_ids
}

output "route_table_nat_az" {
  description = "Availability zone of the NAT instance serving each private route table."
  value       = local.route_table_nat_az
}

output "nat_azs" {
  description = "Availability zones that get a NAT instance."
  value       = local.nat_azs
}

output "vpc_az_maps" {
  description = "alterNAT's vpc_az_maps input: one entry per NAT instance."
  value       = local.vpc_az_maps
}

output "endpoint_subnet_ids" {
  description = "One private subnet per availability zone, for interface endpoints."
  value       = local.endpoint_subnet_ids
}
