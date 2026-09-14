################################################################################
# ECS Service Security Group
################################################################################

module "security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "ecs-service"
  description = "Security group for ECS service ${var.name}"
  vpc_id      = var.vpc_id
  tags        = var.tags

  all_egress_enabled = true

  ingress_rules = local.security_group_ingress_rules
}

locals {
  # Every ingress rule on the service security group, in state-index order.
  # Exposed as an output so the effective ingress can be read and tested.
  security_group_ingress_rules = concat(
    # Load balancer ingress (from LB security group if provided, else VPC CIDR)
    local.enable_load_balancer ? [
      for mapping in local.load_balancer_port_mappings : var.load_balancer_security_group_id != null ? {
        description                  = "Allow traffic from load balancer on port ${mapping.container_port}"
        from_port                    = mapping.container_port
        to_port                      = mapping.container_port
        ip_protocol                  = mapping.protocol
        referenced_security_group_id = var.load_balancer_security_group_id
        } : {
        description = "Allow traffic from load balancer on port ${mapping.container_port}"
        from_port   = mapping.container_port
        to_port     = mapping.container_port
        ip_protocol = mapping.protocol
        cidr_ipv4   = data.aws_vpc.this.cidr_block
      }
    ] : [],
    # Additional CIDR blocks
    flatten([
      for cidr in var.allowed_cidr_blocks : [
        for mapping in local.load_balancer_port_mappings : {
          description = "Allow traffic from ${cidr}"
          from_port   = local.enable_load_balancer ? mapping.container_port : 0
          to_port     = local.enable_load_balancer ? mapping.container_port : 65535
          ip_protocol = mapping.protocol
          cidr_ipv4   = cidr
        }
      ]
    ]),
    # Peer ingress for callers of the service discovery address. The whole
    # VPC may reach the container port unless specific security groups are
    # listed, in which case only those groups may. Appended last: the rules
    # above are index-keyed in state, so inserting earlier would recreate
    # every one of them on upgrade.
    local.enable_service_discovery ? flatten([
      for mapping in local.load_balancer_port_mappings :
      length(var.allowed_security_group_ids) == 0 ? [{
        description = "Allow VPC traffic to the service discovery address on port ${mapping.container_port}"
        from_port   = mapping.container_port
        to_port     = mapping.container_port
        ip_protocol = mapping.protocol
        cidr_ipv4   = data.aws_vpc.this.cidr_block
        }] : [
        for sg in var.allowed_security_group_ids : {
          description                  = "Allow traffic from security group ${sg} on port ${mapping.container_port}"
          from_port                    = mapping.container_port
          to_port                      = mapping.container_port
          ip_protocol                  = mapping.protocol
          referenced_security_group_id = sg
        }
      ]
    ]) : []
  )
}

locals {
  additional_nlb_listener_ipv4_ingress = {
    for pair in setproduct(keys(local.additional_nlb_listeners), var.load_balancer_ingress_cidr_blocks) :
    "${pair[0]}|${pair[1]}" => {
      listener = local.additional_nlb_listeners[pair[0]]
      cidr     = pair[1]
    }
  }
  additional_nlb_listener_ipv6_ingress = {
    for pair in setproduct(keys(local.additional_nlb_listeners), var.load_balancer_ingress_ipv6_cidr_blocks) :
    "${pair[0]}|${pair[1]}" => {
      listener = local.additional_nlb_listeners[pair[0]]
      cidr     = pair[1]
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv4" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? toset(var.load_balancer_ingress_cidr_blocks) : toset([])

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${local.primary_nlb_listener.protocol} traffic on port ${local.primary_nlb_listener.port} from ${each.value}"
  from_port         = local.primary_nlb_listener.port
  to_port           = local.primary_nlb_listener.port
  ip_protocol       = local.primary_nlb_listener.protocol == "UDP" ? "udp" : "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv6" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? toset(var.load_balancer_ingress_ipv6_cidr_blocks) : toset([])

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${local.primary_nlb_listener.protocol} traffic on port ${local.primary_nlb_listener.port} from ${each.value}"
  from_port         = local.primary_nlb_listener.port
  to_port           = local.primary_nlb_listener.port
  ip_protocol       = local.primary_nlb_listener.protocol == "UDP" ? "udp" : "tcp"
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nlb_additional_listener_ipv4" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? local.additional_nlb_listener_ipv4_ingress : {}

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${each.value.listener.protocol} traffic on port ${each.value.listener.port} from ${each.value.cidr}"
  from_port         = each.value.listener.port
  to_port           = each.value.listener.port
  ip_protocol       = each.value.listener.protocol == "UDP" ? "udp" : "tcp"
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "nlb_additional_listener_ipv6" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? local.additional_nlb_listener_ipv6_ingress : {}

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${each.value.listener.protocol} traffic on port ${each.value.listener.port} from ${each.value.cidr}"
  from_port         = each.value.listener.port
  to_port           = each.value.listener.port
  ip_protocol       = each.value.listener.protocol == "UDP" ? "udp" : "tcp"
  cidr_ipv6         = each.value.cidr
}
