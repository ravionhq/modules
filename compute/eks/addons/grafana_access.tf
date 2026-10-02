################################################################################
# In-cluster Grafana on a shared ALB (optional)
#
# Grafana stays a ClusterIP Service; the chosen shared ALB reaches its pods
# through a target group the load balancer controller binds to that Service,
# the same TargetGroupBinding pattern the EKS workload modules use. The ALB
# routes one hostname to it on the HTTPS listener only.
#
# The public ALB puts Grafana's sign-in page on the internet. The private ALB
# keeps it inside the VPC and the networks connected to it, such as a VPN or a
# Tailscale subnet router. Who may sign in is grafana_auth.tf's.
#
# DNS is not managed here. Point the hostname at the chosen ALB's DNS name, and
# make sure one of its HTTPS listener's certificates covers it.
################################################################################

locals {
  grafana_access_enabled = var.grafana_enabled && var.grafana_access.enabled
  grafana_access_public  = var.grafana_access.load_balancer == "public"

  grafana_hostname = try(trimspace(var.grafana_access.hostname), "")

  # Target group names are at most 32 characters and cannot end in a hyphen.
  grafana_target_group_name = trimsuffix(substr("${local.name}-grafana", 0, 32), "-")
}

resource "aws_lb_target_group" "grafana" {
  count = local.grafana_access_enabled ? 1 : 0

  name        = local.grafana_target_group_name
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path    = "/api/health"
    matcher = "200"
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "grafana" {
  count = local.grafana_access_enabled ? 1 : 0

  listener_arn = local.grafana_access_public ? one(module.public_alb[*].https_listener_arn) : one(module.private_alb[*].https_listener_arn)
  priority     = var.grafana_access.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }

  condition {
    host_header {
      values = [local.grafana_hostname]
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.grafana_access_public ? var.public_alb_creation_enabled && var.public_alb_https_enabled : var.private_alb_creation_enabled && var.private_alb_https_enabled
      error_message = "Grafana's load balancer access needs the chosen shared ALB with HTTPS on (public_alb_creation_enabled and public_alb_https_enabled, or the private_alb_ pair). Grafana is never served over plain HTTP."
    }

    precondition {
      condition     = local.grafana_hostname != ""
      error_message = "Grafana's load balancer access needs a hostname, routed on the chosen ALB's HTTPS listener."
    }
  }
}

resource "helm_release" "grafana_alb_binding" {
  count = local.grafana_access_enabled ? 1 : 0

  name      = "ravion-grafana-alb-binding"
  namespace = local.grafana_namespace
  chart     = "${path.module}/charts/grafana-alb-binding"

  create_namespace = true
  upgrade_install  = true

  values = [
    yamlencode({
      name           = local.grafana_release_name
      serviceName    = local.grafana_release_name
      servicePort    = 80
      targetGroupArn = aws_lb_target_group.grafana[0].arn
    }),
  ]

  # The TargetGroupBinding CRD comes with the load balancer controller.
  depends_on = [
    helm_release.lb_controller,
    helm_release.grafana,
    aws_lb_listener_rule.grafana,
  ]
}
