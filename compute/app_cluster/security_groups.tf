################################################################################
# Load Balancer Security Group
#
# Open to the allowed CIDRs on the two listener ports. Out, it reaches the
# router's ports and nothing else.
################################################################################

resource "aws_security_group" "load_balancer" {
  name        = "${var.name}-nlb"
  description = "App Cluster load balancer for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-nlb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer" {
  for_each = {
    for rule in setproduct(["443", "80"], var.ingress_cidr_blocks) : "${rule[0]}-${rule[1]}" => {
      port = tonumber(rule[0])
      cidr = rule[1]
    }
  }

  security_group_id = aws_security_group.load_balancer.id
  description       = "Allow ${each.value.port == 443 ? "HTTPS" : "HTTP"} from ${each.value.cidr}"

  ip_protocol = "tcp"
  from_port   = each.value.port
  to_port     = each.value.port
  cidr_ipv4   = each.value.cidr

  tags = merge(local.tags, {
    Name = "${var.name}-nlb-ingress"
  })
}

resource "aws_vpc_security_group_egress_rule" "load_balancer" {
  for_each = local.router_ports

  security_group_id = aws_security_group.load_balancer.id
  description       = "Allow ${local.router_port_purposes[each.key]} to the router"

  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.router.id

  tags = merge(local.tags, {
    Name = "${var.name}-nlb-egress"
  })
}

################################################################################
# Router Security Group
#
# Ravion launches the router instance in this group. In, only the load
# balancer reaches the router, on the router's three ports; no CIDR does. Out,
# the router reaches HTTPS (the Ravion API, AWS APIs) and, inside the VPC, the
# app port range the sandbox hosts serve the apps on, so a router cannot be
# turned against anything else in the network.
#
# The hosts are the execution environment's, in its security group. While the
# router runs, Ravion adds the rule there that admits this group on the app
# port range, and removes it when the router stops, before a destroy of this
# stack: no rule outside the stack ever names the router's group when
# Terraform deletes it.
################################################################################

resource "aws_security_group" "router" {
  name        = local.router_name
  description = "App Cluster router for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = local.router_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "router" {
  for_each = local.router_ports

  security_group_id = aws_security_group.router.id
  description       = "Allow ${local.router_port_purposes[each.key]} from the load balancer"

  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.load_balancer.id

  tags = merge(local.tags, {
    Name = "${local.router_name}-ingress"
  })
}

resource "aws_vpc_security_group_egress_rule" "router_https" {
  for_each = local.router_https_ports

  security_group_id = aws_security_group.router.id
  description       = "Allow HTTPS to the Ravion API and AWS APIs"

  ip_protocol = "tcp"
  from_port   = tonumber(each.value)
  to_port     = tonumber(each.value)
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.router_name}-egress-https"
  })
}

resource "aws_vpc_security_group_egress_rule" "router_to_sandbox_hosts" {
  for_each = local.vpc_cidr_blocks

  security_group_id = aws_security_group.router.id
  description       = "Allow app ports on the sandbox hosts in ${each.value}"

  ip_protocol = "tcp"
  from_port   = local.app_port_range.from
  to_port     = local.app_port_range.to
  cidr_ipv4   = each.value

  tags = merge(local.tags, {
    Name = "${local.router_name}-egress-apps"
  })
}
