################################################################################
# HTTP Listener
################################################################################

resource "aws_lb_listener" "http" {
  count = local.create_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.http_listener_port
  protocol          = "HTTP"

  # If HTTPS is enabled and redirect is enabled, redirect to HTTPS
  # Otherwise, return a fixed response
  dynamic "default_action" {
    for_each = var.http_to_https_redirect_enabled && local.create_https_listener ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = tostring(var.https_listener_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = !var.http_to_https_redirect_enabled || !local.create_https_listener ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = var.default_action_content_type
        message_body = var.default_action_message
        status_code  = tostring(var.default_action_status_code)
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-http"
  })
}

################################################################################
# HTTPS Listener
################################################################################

resource "aws_lb_listener" "https" {
  count = local.create_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.https_listener_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = try(var.certificate_arns[0], null)

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = var.default_action_content_type
      message_body = var.default_action_message
      status_code  = tostring(var.default_action_status_code)
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-https"
  })

  lifecycle {
    precondition {
      condition     = length(var.certificate_arns) > 0
      error_message = "At least one entry in certificate_arns is required when https_listener_enabled is true."
    }
  }
}

################################################################################
# Additional Certificates (SNI)
################################################################################

resource "aws_lb_listener_certificate" "additional" {
  for_each = local.create_https_listener ? toset(slice(var.certificate_arns, 1, length(var.certificate_arns))) : toset([])

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}
