################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

# Resolve the load balancer behind the listener so its DNS name and zone ID can
# be exposed as outputs, for CloudFront origins, DNS records, and the module's
# dashboard link.
data "aws_lb_listener" "attached" {
  count = local.enable_load_balancer ? 1 : 0

  arn = var.listener_arn
}

data "aws_lb" "attached" {
  count = local.enable_load_balancer ? 1 : 0

  arn = data.aws_lb_listener.attached[0].load_balancer_arn
}

# The load balancer's subnets, so a workload's ingress allow-list can admit the
# load balancer nodes (health checks and forwarded requests) by CIDR without
# opening the whole VPC.
data "aws_subnet" "load_balancer" {
  for_each = local.enable_load_balancer ? data.aws_lb.attached[0].subnets : toset([])

  id = each.value
}
