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
# the router reaches HTTPS (the Ravion API, AWS APIs) and the app port range
# on the sandbox hosts, so a router cannot be turned against anything else in
# the network.
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
  security_group_id = aws_security_group.router.id
  description       = "Allow app ports on the sandbox hosts"

  ip_protocol                  = "tcp"
  from_port                    = local.app_port_range.from
  to_port                      = local.app_port_range.to
  referenced_security_group_id = aws_security_group.sandbox_hosts.id

  tags = merge(local.tags, {
    Name = "${local.router_name}-egress-apps"
  })
}

################################################################################
# Sandbox Hosts Security Group
#
# Ravion launches the cluster's sandbox hosts in this group (sandbox_pool.tf).
# In, only the router reaches them, on the app port range. Out, the hosts
# reach any IPv4 address: they dial Ravion, pull images and packages, and run
# the apps, which call whatever they call.
#
# The router's rule belongs to this stack, so a destroy removes it with the
# groups instead of leaving a rule that names the router's group behind.
################################################################################

resource "aws_security_group" "sandbox_hosts" {
  name        = local.hosts_name
  description = "App Cluster sandbox hosts for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = local.hosts_name
  })
}

resource "aws_vpc_security_group_ingress_rule" "sandbox_hosts_from_router" {
  security_group_id = aws_security_group.sandbox_hosts.id
  description       = "ravion app router to sandbox hosts"

  ip_protocol                  = "tcp"
  from_port                    = local.app_port_range.from
  to_port                      = local.app_port_range.to
  referenced_security_group_id = aws_security_group.router.id

  tags = merge(local.tags, {
    Name = "${local.hosts_name}-from-router"
  })
}

resource "aws_vpc_security_group_egress_rule" "sandbox_hosts" {
  security_group_id = aws_security_group.sandbox_hosts.id
  description       = "Allow all outbound IPv4 traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.hosts_name}-egress"
  })
}
