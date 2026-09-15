################################################################################
# Target Groups
#
# A production (tg-1) + alternate (tg-2) pair is created for ALB so deployment
# strategy remains a per-deployment decision. The rolling-only nlb_listeners
# shape creates one target group per listener and omits the unused alternate.
################################################################################

resource "aws_lb_target_group" "tg_1" {
  count = local.enable_load_balancer ? 1 : 0

  name        = "${substr(local.target_group_base_name, 0, min(length(var.name), 24))}-tg-1"
  port        = local.primary_target_group_port
  protocol    = local.primary_target_group_protocol
  vpc_id      = var.vpc_id
  target_type = var.load_balancer_attachment.target_group.target_type

  deregistration_delay = var.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? var.load_balancer_attachment.target_group.slow_start : null

  health_check {
    enabled             = var.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.primary_health_check_protocol) ? var.load_balancer_attachment.target_group.health_check.path : null
    port                = var.load_balancer_attachment.target_group.health_check.port
    protocol            = local.primary_health_check_protocol
    matcher             = contains(["HTTP", "HTTPS"], local.primary_health_check_protocol) ? var.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = var.load_balancer_attachment.target_group.health_check.interval
    timeout             = var.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = var.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = var.load_balancer_attachment.target_group.stickiness != null ? [var.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? stickiness.value.cookie_duration : null
      cookie_name     = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.tags, {
    Name           = "${var.name}-tg-1"
    DeploymentType = "tg-1"
  })

  lifecycle {
    create_before_destroy = true
    # Re-adopting a pre-existing target group via the moved block (old name
    # suffix `-tg`) must not force replacement just because the configured
    # name is now `-tg-1`: the listener rule ignores `action`, so it would
    # never repoint to the replacement and the old TG's destroy would fail
    # ("currently in use by a listener rule"). Ignoring `name` keeps the
    # existing TG (and its ARN) in place; fresh services still get `-tg-1`.
    ignore_changes = [name]
  }
}

resource "aws_lb_target_group" "tg_2" {
  count = local.traffic_shift_infrastructure_enabled ? 1 : 0

  name        = "${substr(local.target_group_base_name, 0, min(length(var.name), 24))}-tg-2"
  port        = local.primary_target_group_port
  protocol    = local.primary_target_group_protocol
  vpc_id      = var.vpc_id
  target_type = var.load_balancer_attachment.target_group.target_type

  deregistration_delay = var.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? var.load_balancer_attachment.target_group.slow_start : null

  health_check {
    enabled             = var.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.primary_health_check_protocol) ? var.load_balancer_attachment.target_group.health_check.path : null
    port                = var.load_balancer_attachment.target_group.health_check.port
    protocol            = local.primary_health_check_protocol
    matcher             = contains(["HTTP", "HTTPS"], local.primary_health_check_protocol) ? var.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = var.load_balancer_attachment.target_group.health_check.interval
    timeout             = var.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = var.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = var.load_balancer_attachment.target_group.stickiness != null ? [var.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? stickiness.value.cookie_duration : null
      cookie_name     = contains(["HTTP", "HTTPS"], local.primary_target_group_protocol) ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.tags, {
    Name           = "${var.name}-tg-2"
    DeploymentType = "tg-2"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "nlb_additional" {
  for_each = local.additional_nlb_listeners

  name        = "${substr(local.target_group_base_name, 0, min(length(var.name), 18))}-${each.key}-tg"
  port        = each.value.container_port
  protocol    = each.value.target_protocol
  vpc_id      = var.vpc_id
  target_type = var.load_balancer_attachment.target_group.target_type

  deregistration_delay = var.load_balancer_attachment.target_group.deregistration_delay

  health_check {
    enabled             = var.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.additional_nlb_health_check_protocols[each.key]) ? var.load_balancer_attachment.target_group.health_check.path : null
    port                = var.load_balancer_attachment.target_group.health_check.port
    protocol            = local.additional_nlb_health_check_protocols[each.key]
    matcher             = contains(["HTTP", "HTTPS"], local.additional_nlb_health_check_protocols[each.key]) ? var.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = var.load_balancer_attachment.target_group.health_check.interval
    timeout             = var.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = var.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = var.load_balancer_attachment.target_group.stickiness != null ? [var.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled = stickiness.value.enabled
      type    = stickiness.value.type
    }
  }

  tags = merge(local.tags, {
    Name         = "${var.name}-${each.key}-target-group"
    ListenerPort = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}
