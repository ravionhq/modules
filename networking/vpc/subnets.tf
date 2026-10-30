################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = local.subnet_count

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = local.public_subnet_cidrs[count.index]
  availability_zone               = local.azs[count.index]
  map_public_ip_on_launch         = var.public_subnet_map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.ipv6_enabled
  ipv6_cidr_block                 = var.ipv6_enabled ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index) : null

  tags = merge(local.tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Tier = "public"
  })

  lifecycle {
    precondition {
      condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == local.subnet_count
      error_message = "The number of public_subnet_cidrs (${var.public_subnet_cidrs != null ? length(var.public_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }
  }
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = local.private_subnet_count

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = local.private_subnet_cidrs[count.index]
  availability_zone               = local.azs[count.index]
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = var.ipv6_enabled
  ipv6_cidr_block                 = var.ipv6_enabled ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + 10) : null

  tags = merge(local.tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Tier = "private"
  })

  lifecycle {
    precondition {
      condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == local.subnet_count
      error_message = "The number of private_subnet_cidrs (${var.private_subnet_cidrs != null ? length(var.private_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }
  }
}

################################################################################
# Secondary CIDR Subnets
################################################################################

# IPv6 stays on the primary subnets: the VPC's IPv6 block is already split
# between them.
resource "aws_subnet" "secondary_public" {
  count = local.secondary_subnet_count

  # The association's VPC ID orders the subnets after the CIDR is associated.
  vpc_id                  = aws_vpc_ipv4_cidr_block_association.secondary[0].vpc_id
  cidr_block              = local.secondary_public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.public_subnet_map_public_ip_on_launch

  tags = merge(local.tags, {
    Name = "${var.name}-secondary-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "secondary_private" {
  count = local.secondary_private_subnet_count

  vpc_id                  = aws_vpc_ipv4_cidr_block_association.secondary[0].vpc_id
  cidr_block              = local.secondary_private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name}-secondary-private-${local.azs[count.index]}"
    Tier = "private"
  })
}
