################################################################################
# Listeners
################################################################################

# TLS ends here. No ALPN policy: one that offers HTTP/2 would hand the router
# HTTP/2 frames over plain TCP, and the router is sent HTTP/1.1.
resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = ravion_aws_acm_certificate.this.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traffic.arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-tls"
  })
}

# A load balancer that does not speak HTTP cannot redirect, so plain HTTP goes
# to the router, which answers it with a redirect to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redirect.arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-http"
  })
}
