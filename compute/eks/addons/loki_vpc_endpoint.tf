################################################################################
# Loki query endpoint inside the VPC
#
# Loki is otherwise reachable only in-cluster (loki.tf). This puts its HTTP API
# behind an internal Network Load Balancer for clients outside the cluster, such
# as an Amazon Managed Grafana workspace with a VPC connection.
#
# Only members of the Loki client security group reach the load balancer. A
# client attaches that group rather than being listed here, so the add-ons never
# need to know who reads their logs. The controller binds the Loki pods to the
# target group through a TargetGroupBinding (charts/loki-vpc-endpoint), the
# shared-load-balancer pattern load_balancers.tf uses for workloads.
################################################################################

locals {
  loki_vpc_endpoint_enabled = var.loki_vpc_endpoint_enabled && local.loki_enabled
  loki_http_port            = 3100
}

module "loki_client_security_group" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  source = "../../../networking/security-groups"

  name        = local.name
  name_suffix = "loki-client"
  description = "Clients that may query Loki on ${var.cluster_name} through its internal load balancer"
  vpc_id      = local.vpc_id
  tags        = local.tags

  ingress_rules = []
  egress_rules = [{
    description                  = "Loki queries to the internal load balancer"
    from_port                    = local.loki_http_port
    to_port                      = local.loki_http_port
    ip_protocol                  = "tcp"
    referenced_security_group_id = module.loki_nlb[0].security_group_id
  }]
}

module "loki_nlb" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  source = "../../../networking/nlb"

  name   = "${local.name}-loki"
  tags   = local.tags
  vpc_id = local.vpc_id

  subnet_ids                     = var.node_subnet_ids
  internal_load_balancer_enabled = true
  deletion_protection_enabled    = var.load_balancer_deletion_protection_enabled

  # No CIDR ingress: the rule below admits the client security group alone.
  listener_ports      = []
  ingress_cidr_blocks = []
}

resource "aws_vpc_security_group_ingress_rule" "loki_nlb_from_clients" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  security_group_id            = module.loki_nlb[0].security_group_id
  description                  = "Loki queries from the Loki client security group"
  ip_protocol                  = "tcp"
  from_port                    = local.loki_http_port
  to_port                      = local.loki_http_port
  referenced_security_group_id = module.loki_client_security_group[0].security_group_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_loki_nlb" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  description                  = "Loki load balancer to the Loki pods (${var.cluster_name})"
  ip_protocol                  = "tcp"
  from_port                    = local.loki_http_port
  to_port                      = local.loki_http_port
  referenced_security_group_id = module.loki_nlb[0].security_group_id

  tags = local.tags
}

resource "aws_lb_target_group" "loki" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  name        = "${local.name}-loki"
  port        = local.loki_http_port
  protocol    = "TCP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    path     = "/ready"
  }

  tags = local.tags
}

resource "aws_lb_listener" "loki" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  load_balancer_arn = module.loki_nlb[0].nlb_arn
  port              = local.loki_http_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.loki[0].arn
  }

  tags = local.tags
}

resource "helm_release" "loki_vpc_endpoint" {
  count = local.loki_vpc_endpoint_enabled ? 1 : 0

  name            = "${local.loki_release_name}-vpc-endpoint"
  namespace       = local.logs_namespace
  chart           = "${path.module}/charts/loki-vpc-endpoint"
  upgrade_install = true

  values = [yamlencode({
    serviceName    = local.loki_release_name
    servicePort    = local.loki_http_port
    targetGroupArn = aws_lb_target_group.loki[0].arn
  })]

  depends_on = [
    # The binding names Loki's Service, and only the controller reconciles it.
    helm_release.loki,
    helm_release.lb_controller,
  ]

  lifecycle {
    precondition {
      condition     = var.cluster_security_group_id != null && length(var.node_subnet_ids) > 0
      error_message = "The Loki VPC endpoint needs the cluster security group ID, to admit the load balancer, and node subnet IDs, to place it."
    }
  }
}
