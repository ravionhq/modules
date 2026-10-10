################################################################################
# Gateway Endpoints (S3, DynamoDB)
################################################################################

# Each gateway endpoint is attached to the route tables of the subnets its list
# names, so only those subnets reach the service through it.
locals {
  gateway_endpoint_route_table_ids = {
    for service, subnets in {
      s3       = var.vpc_endpoint_s3_gateway_subnets
      dynamodb = var.vpc_endpoint_dynamodb_gateway_subnets
      } : service => concat(
      contains(subnets, "public") ? [aws_route_table.public.id] : [],
      contains(subnets, "private") ? aws_route_table.private[*].id : [],
      [for key, table in local.private_subnet_group_route_tables : aws_route_table.private_group[key].id if contains(subnets, table.group)],
    )
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = length(var.vpc_endpoint_s3_gateway_subnets) > 0 ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_endpoint_route_table_ids.s3

  tags = merge(local.tags, {
    Name = "${var.name}-s3"
  })

  lifecycle {
    precondition {
      condition     = alltrue([for name in var.vpc_endpoint_s3_gateway_subnets : contains(local.gateway_endpoint_subnet_names, name)])
      error_message = "vpc_endpoint_s3_gateway_subnets names ${join(", ", setsubtract(var.vpc_endpoint_s3_gateway_subnets, local.gateway_endpoint_subnet_names))}, which is neither public, private nor a private subnet group."
    }
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = length(var.vpc_endpoint_dynamodb_gateway_subnets) > 0 ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_endpoint_route_table_ids.dynamodb

  tags = merge(local.tags, {
    Name = "${var.name}-dynamodb"
  })

  lifecycle {
    precondition {
      condition     = alltrue([for name in var.vpc_endpoint_dynamodb_gateway_subnets : contains(local.gateway_endpoint_subnet_names, name)])
      error_message = "vpc_endpoint_dynamodb_gateway_subnets names ${join(", ", setsubtract(var.vpc_endpoint_dynamodb_gateway_subnets, local.gateway_endpoint_subnet_names))}, which is neither public, private nor a private subnet group."
    }
  }
}

################################################################################
# Interface Endpoints (PrivateLink)
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  count = length(local.vpc_endpoint_interface_services) > 0 ? 1 : 0

  name_prefix = "${var.name}-vpc-endpoints-"
  description = "Allow HTTPS from the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-endpoints"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.vpc_endpoint_interface_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-${each.value}"
  })
}
