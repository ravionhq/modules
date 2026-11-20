################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "Dev box ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

# A dev box installs packages, clones repositories, and calls APIs, so all
# outbound traffic is allowed. Session Manager also connects outbound.
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound IPv4 traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound IPv6 traffic"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value

  tags = local.tags
}
