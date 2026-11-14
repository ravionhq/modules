################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = var.dns_support_enabled
  enable_dns_hostnames             = var.dns_hostnames_enabled
  assign_generated_ipv6_cidr_block = var.ipv6_enabled

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = local.subnet_count >= 1
      error_message = "At least one availability zone must be available or specified to create VPC subnets."
    }

    precondition {
      condition     = local.subnet_count <= length(local.selected_availability_zones)
      error_message = "Requested ${local.subnet_count} subnet pairs but only ${length(local.selected_availability_zones)} availability zones are available or specified."
    }

    precondition {
      condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == local.subnet_count
      error_message = "The number of public_subnet_cidrs (${var.public_subnet_cidrs != null ? length(var.public_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == local.subnet_count
      error_message = "The number of private_subnet_cidrs (${var.private_subnet_cidrs != null ? length(var.private_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = var.private_subnets_enabled || !var.nat_gateway_enabled
      error_message = "A NAT gateway needs private subnets to route; disable nat_gateway_enabled or enable private_subnets_enabled."
    }

    precondition {
      condition     = var.private_subnets_enabled || length(local.vpc_endpoint_interface_services) == 0
      error_message = "Interface VPC endpoints are created in the private subnets; remove vpc_endpoint_interface_services or enable private_subnets_enabled."
    }

    precondition {
      condition     = var.secondary_public_subnet_cidrs == null || length(var.secondary_public_subnet_cidrs) == local.subnet_count
      error_message = "The number of secondary_public_subnet_cidrs (${var.secondary_public_subnet_cidrs != null ? length(var.secondary_public_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = var.secondary_private_subnet_cidrs == null || length(var.secondary_private_subnet_cidrs) == local.subnet_count
      error_message = "The number of secondary_private_subnet_cidrs (${var.secondary_private_subnet_cidrs != null ? length(var.secondary_private_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = local.supplied_nat_eip_allocation_ids == null || !var.nat_gateway_enabled || length(local.supplied_nat_eip_allocation_ids) == local.nat_gateway_count
      error_message = "The number of nat_gateway_eip_allocation_ids must equal 1 for single-NAT mode, or subnet_count (${local.subnet_count}) for HA mode."
    }
  }
}

################################################################################
# Secondary CIDR
################################################################################

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = var.secondary_vpc_cidr != null ? 1 : 0

  vpc_id     = aws_vpc.this.id
  cidr_block = var.secondary_vpc_cidr
}
