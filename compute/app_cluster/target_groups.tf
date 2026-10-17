################################################################################
# Target Groups
################################################################################

# Instance targets keep the client's address, so the router sees who asked.
# Both groups are healthy when the router's health endpoint answers.

resource "aws_lb_target_group" "traffic" {
  name        = "${local.target_group_name_prefix}-https"
  port        = local.router_ports.traffic
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  preserve_client_ip   = true
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    port                = local.router_ports.health
    path                = "/healthz"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, {
    Name                   = "${var.name}-https"
    (local.router_tag_key) = var.module_instance_id
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "redirect" {
  name        = "${local.target_group_name_prefix}-http"
  port        = local.router_ports.redirect
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  preserve_client_ip   = true
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    port                = local.router_ports.health
    path                = "/healthz"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, {
    Name                   = "${var.name}-http"
    (local.router_tag_key) = var.module_instance_id
  })

  lifecycle {
    create_before_destroy = true
  }
}
