################################################################################
# Load Balancer Security Group
#
# Open to the allowed CIDRs on the two listener ports. Out, it reaches the
# router's ports and nothing else.
################################################################################

resource "aws_security_group" "load_balancer" {
  name        = "${var.name}-nlb"
  description = "Preview ingress load balancer for ${var.name}"
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
# In, only the load balancer reaches the router, on the router's three ports;
# no CIDR does. Out, the router reaches HTTPS (the Ravion API, AWS APIs) and
# the preview port range on the sandbox host groups, so a router cannot be
# turned against anything else in the network.
################################################################################

resource "aws_security_group" "router" {
  name        = local.router_name
  description = "Preview router for ${var.name}"
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

resource "aws_vpc_security_group_egress_rule" "router_previews" {
  for_each = local.sandbox_host_security_groups

  security_group_id = aws_security_group.router.id
  description       = "Allow sandbox preview ports on the ${each.key} sandbox hosts"

  ip_protocol                  = "tcp"
  from_port                    = local.preview_port_range.from
  to_port                      = local.preview_port_range.to
  referenced_security_group_id = each.value

  tags = merge(local.tags, {
    Name = "${local.router_name}-egress-previews"
  })
}

################################################################################
# Sandbox Hosts
#
# The other end of the router's preview egress: each sandbox host security
# group admits the router's group on the preview port range. The rule belongs
# to this module, so a destroy removes it before the router's group, which AWS
# keeps for as long as another group's rule names it.
################################################################################

resource "aws_vpc_security_group_ingress_rule" "sandbox_hosts" {
  for_each = local.sandbox_host_security_groups

  security_group_id = each.value
  description       = "Allow sandbox previews from the ${var.name} preview router"

  ip_protocol                  = "tcp"
  from_port                    = local.preview_port_range.from
  to_port                      = local.preview_port_range.to
  referenced_security_group_id = aws_security_group.router.id

  tags = merge(local.tags, {
    Name = "${local.router_name}-previews"
  })
}
