################################################################################
# ALB Listener Rule
#
# Routes matching requests on the shared listener from compute/eks/addons to
# this workload's target group. A port of compute/ecs_service's production rule
# minus the traffic-shift machinery: no green/test rule, no group stickiness on
# the forward action (that exists only so ELBv2 accepts the weighted forward
# ECS writes mid-deployment), and no ignore_changes on `action`, because on EKS
# nothing outside Terraform ever rewrites this rule.
#
# Created only when var.listener_arn is set, alongside the target group it
# forwards to.
################################################################################

resource "aws_lb_listener_rule" "this" {
  count = local.enable_load_balancer ? 1 : 0

  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "path-pattern"]
    content {
      path_pattern {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "host-header"]
    content {
      host_header {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "http-header"]
    content {
      http_header {
        http_header_name = condition.value.values[0]
        values           = slice(condition.value.values, 1, length(condition.value.values))
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "http-request-method"]
    content {
      http_request_method {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "query-string"]
    content {
      query_string {
        key   = try(condition.value.values[0], null)
        value = try(condition.value.values[1], condition.value.values[0])
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.listener_rule_conditions : c if c.type == "source-ip"]
    content {
      source_ip {
        values = condition.value.values
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-rule"
  })
}
