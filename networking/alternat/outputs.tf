output "aws_account_id" {
  description = "AWS account ID the NAT instances run in."
  value       = data.aws_vpc.this.owner_id
}

output "region" {
  description = "AWS region the NAT instances run in."
  value       = var.region
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = var.vpc_id
}

################################################################################
# NAT instances
################################################################################

output "nat_instance_public_ips" {
  description = "Public IPs internet traffic leaves from while the NAT instances are healthy. Add them, and the fallback NAT gateway IPs, to partner allowlists."
  value = (
    length(var.nat_instance_eip_allocation_ids) > 0
    ? [for id in var.nat_instance_eip_allocation_ids : data.aws_eip.nat_instance[id].public_ip]
    : module.alternat.nat_instance_eips
  )
}

output "nat_instances" {
  description = "One entry per NAT instance: its availability zone, Auto Scaling group, connectivity tester log group, and the route tables it serves."
  value = [
    for index, az_map in local.vpc_az_maps : {
      availability_zone                  = az_map.az
      public_subnet_id                   = az_map.public_subnet_id
      route_table_ids                    = az_map.route_table_ids
      autoscaling_group_name             = module.alternat.autoscaling_group_names[index]
      connectivity_tester_function_name  = "${local.connectivity_tester_function_name}-${az_map.az}"
      connectivity_tester_log_group_name = "/aws/lambda/${local.connectivity_tester_function_name}-${az_map.az}"
    }
  ]
}

output "nat_instance_availability_zones" {
  description = "Availability zones with a NAT instance."
  value       = local.nat_azs
}

output "nat_instance_security_group_id" {
  description = "Security group of the NAT instances."
  value       = module.alternat.nat_instance_security_group_id
}

output "autoscaling_group_names" {
  description = "Auto Scaling groups of the NAT instances, one per NAT instance."
  value       = module.alternat.autoscaling_group_names
}

output "nat_instance_architecture" {
  description = "CPU architecture of the NAT instances, derived from the instance type."
  value       = local.architecture
}

################################################################################
# Routing
################################################################################

output "route_table_ids" {
  description = "Private route tables whose 0.0.0.0/0 route alterNAT manages."
  value       = local.route_table_ids
}

output "route_table_nat_availability_zones" {
  description = "Availability zone of the NAT instance serving each private route table."
  value       = local.route_table_nat_az
}

################################################################################
# Fallback NAT gateway
################################################################################

output "fallback_nat_gateway_id" {
  description = "NAT gateway every NAT instance fails over to. Empty when each fails over to the NAT gateway in its own public subnet."
  value       = local.fallback_nat_gateway_id
}

output "fallback_nat_gateway_ids" {
  description = "Existing NAT gateways the NAT instances fail over to. Empty in create mode."
  value = (
    local.fallback_nat_gateway_id != "" ? [local.fallback_nat_gateway_id] :
    distinct([for gateway in data.aws_nat_gateway.existing : gateway.id if contains([for az_map in local.vpc_az_maps : az_map.public_subnet_id], gateway.subnet_id)])
  )
}

output "fallback_nat_gateway_public_ips" {
  description = "Public IPs of the standby NAT gateways created by this module (create mode)."
  value       = module.alternat.nat_gateway_eips
}

################################################################################
# Lambda functions
################################################################################

output "connectivity_tester_function_names" {
  description = "Connectivity tester Lambda functions, one per NAT instance."
  value       = [for az in local.nat_azs : "${local.connectivity_tester_function_name}-${az}"]
}

output "connectivity_tester_log_group_names" {
  description = "CloudWatch log groups of the connectivity tester Lambda functions."
  value       = [for az in local.nat_azs : "/aws/lambda/${local.connectivity_tester_function_name}-${az}"]
}

output "autoscaling_hook_function_name" {
  description = "Lambda function that moves routes to the fallback NAT gateway when a NAT instance terminates."
  value       = local.autoscaling_hook_function_name
}

output "autoscaling_hook_log_group_name" {
  description = "CloudWatch log group of the Auto Scaling hook Lambda function."
  value       = "/aws/lambda/${local.autoscaling_hook_function_name}"
}

################################################################################
# VPC endpoints
################################################################################

output "ec2_vpc_endpoint_id" {
  description = "ID of the EC2 interface endpoint, if created."
  value       = try(aws_vpc_endpoint.ec2[0].id, null)
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 gateway endpoint, if created."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "dynamodb_vpc_endpoint_id" {
  description = "ID of the DynamoDB gateway endpoint, if created."
  value       = try(aws_vpc_endpoint.dynamodb[0].id, null)
}
