################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = local.subnet_count

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = local.public_subnet_cidrs[count.index]
  availability_zone               = local.azs[count.index]
  map_public_ip_on_launch         = false
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
  count = local.subnet_count

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
# Private Subnet Groups
################################################################################

resource "aws_subnet" "private_group" {
  for_each = local.private_subnet_group_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = try(var.private_subnet_groups[each.value.group].cidrs[each.value.index], null)
  availability_zone       = local.azs[each.value.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name        = "${var.name}-${each.value.group}-${local.azs[each.value.index]}"
    Tier        = "private"
    SubnetGroup = each.value.group
  })

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_groups[each.value.group].cidrs) == local.subnet_count
      error_message = "Private subnet group ${each.value.group} has ${length(var.private_subnet_groups[each.value.group].cidrs)} cidrs; it needs one per subnet pair (${local.subnet_count})."
    }
  }
}
