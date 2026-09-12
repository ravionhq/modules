################################################################################
# Target Group
#
# A single IP-mode target group the AWS Load Balancer Controller registers pod
# IPs into, driven by the TargetGroupBinding the rvn-eks-web chart renders from
# the target_group_arn output.
#
# Unlike compute/ecs_service there is no tg-2: the 2026-08-06 load balancer ADR
# on ENG-5033 scopes EKS v1 to rolling Deployment updates, so there is no
# alternate target group, no test listener rule, and no traffic-shift
# controller rewriting the forward action. Nothing external mutates this target
# group, which is why it carries no ignore_changes.
#
# Created only when var.listener_arn is set. Worker and cron workloads reuse
# this root module for its ECR repository alone and leave the listener null.
################################################################################

resource "aws_lb_target_group" "this" {
  count = local.enable_load_balancer ? 1 : 0

  name        = local.target_group_name
  port        = var.container_port
  protocol    = var.target_group_protocol
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.target_group_deregistration_delay
  slow_start           = var.target_group_slow_start

  health_check {
    enabled             = var.target_group_health_check.enabled
    path                = var.target_group_health_check.path
    port                = var.target_group_health_check.port
    protocol            = local.health_check_protocol
    matcher             = var.target_group_health_check.matcher
    interval            = var.target_group_health_check.interval
    timeout             = var.target_group_health_check.timeout
    healthy_threshold   = var.target_group_health_check.healthy_threshold
    unhealthy_threshold = var.target_group_health_check.unhealthy_threshold
  }

  stickiness {
    enabled         = var.target_group_stickiness.enabled
    type            = var.target_group_stickiness.type
    cookie_duration = var.target_group_stickiness.cookie_duration
    cookie_name     = var.target_group_stickiness.type == "app_cookie" ? var.target_group_stickiness.cookie_name : null
  }

  tags = merge(local.tags, {
    Name = "${var.name}-tg"
  })

  # The listener rule forwards to this ARN, so a replacement has to exist
  # before the original is destroyed or the destroy fails with "currently in
  # use by a listener rule".
  lifecycle {
    create_before_destroy = true
  }
}
