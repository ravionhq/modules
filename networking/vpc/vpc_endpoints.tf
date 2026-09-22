################################################################################
# Gateway Endpoints (S3, DynamoDB)
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.vpc_endpoint_s3_gateway_enabled ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], aws_route_table.private[*].id)

  tags = merge(local.tags, {
    Name = "${var.name}-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.vpc_endpoint_dynamodb_gateway_enabled ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], aws_route_table.private[*].id)

  tags = merge(local.tags, {
    Name = "${var.name}-dynamodb"
  })
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
