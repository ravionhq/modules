################################################################################
# EC2 interface endpoint
################################################################################

# The connectivity tester calls the EC2 API to fail over exactly when internet
# egress is broken, so it must reach EC2 without the NAT.
resource "aws_security_group" "ec2_endpoint" {
  count = var.ec2_endpoint_enabled ? 1 : 0

  name_prefix = "${var.name}-ec2-endpoint-"
  description = "HTTPS from the VPC to the EC2 interface endpoint used by alterNAT failover."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-ec2-endpoint"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_endpoint_ipv4" {
  for_each = var.ec2_endpoint_enabled ? toset(local.vpc_ipv4_cidr_blocks) : toset([])

  security_group_id = aws_security_group.ec2_endpoint[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.key

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ec2_endpoint_ipv6" {
  for_each = var.ec2_endpoint_enabled ? toset(local.vpc_ipv6_cidr_blocks) : toset([])

  security_group_id = aws_security_group.ec2_endpoint[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.key

  tags = local.tags
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.ec2_endpoint_enabled ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.placement.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.ec2_endpoint[0].id]

  tags = merge(local.tags, {
    Name = "${var.name}-ec2"
  })
}

################################################################################
# Gateway endpoints
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.s3_gateway_endpoint_enabled ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids

  tags = merge(local.tags, {
    Name = "${var.name}-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.dynamodb_gateway_endpoint_enabled ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids

  tags = merge(local.tags, {
    Name = "${var.name}-dynamodb"
  })
}
