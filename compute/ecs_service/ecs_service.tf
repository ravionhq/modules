################################################################################
# ECS Service
################################################################################

resource "aws_ecs_service" "this" {
  name    = var.name
  cluster = var.cluster_arn

  task_definition = aws_ecs_task_definition.this.arn

  desired_count = var.desired_count

  # Launch type or capacity provider strategy
  launch_type = length(var.capacity_provider_strategies) == 0 ? var.launch_type : null

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Platform version for Fargate
  platform_version = var.launch_type == "FARGATE" ? var.platform_version : null

  # Network configuration (required for awsvpc network mode)
  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = var.subnet_ids
      security_groups  = concat([module.security_group.security_group_id], var.security_group_ids)
      assign_public_ip = var.public_ip_assignment_enabled
    }
  }

  # Deployment controller
  deployment_controller {
    type = local.deployment_controller_type
  }

  # Deployment circuit breaker (rolling strategy only — native
  # traffic-shift strategies have their own rollback semantics)
  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_type == "rolling" && var.deployment_circuit_breaker.enable ? [1] : []
    content {
      enable   = var.deployment_circuit_breaker.enable
      rollback = var.deployment_circuit_breaker.rollback
    }
  }

  # Native deployment strategy. Seeds the strategy + traffic-shift
  # tuning at create time; the Flightcontrol deploy manager passes the
  # authoritative deploymentConfiguration (including pause lifecycle
  # hooks) on every UpdateService call, so this block is in
  # ignore_changes below.
  dynamic "deployment_configuration" {
    for_each = local.is_native_traffic_shift ? [1] : []
    content {
      strategy             = local.deployment_strategy
      bake_time_in_minutes = var.deployment_strategy_config.bake_time_in_minutes

      dynamic "canary_configuration" {
        for_each = var.deployment_type == "canary" ? [1] : []
        content {
          canary_percent              = var.deployment_strategy_config.canary.canary_percent
          canary_bake_time_in_minutes = var.deployment_strategy_config.canary.canary_bake_time_in_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = var.deployment_type == "linear" ? [1] : []
        content {
          step_percent              = var.deployment_strategy_config.linear.step_percent
          step_bake_time_in_minutes = var.deployment_strategy_config.linear.step_bake_time_in_minutes
        }
      }
    }
  }

  # Deployment min/max healthy percent
  deployment_minimum_healthy_percent = var.deployment_type == "rolling" ? var.deployment_minimum_healthy_percent : null
  deployment_maximum_percent         = var.deployment_type == "rolling" ? var.deployment_maximum_percent : null

  # Load balancer configuration. advanced_configuration is always wired
  # (production + alternate target groups, listener rule, infrastructure
  # role) so the deployment strategy stays a per-deployment decision:
  # rolling deployments serve from the production target group (tg-1)
  # only, while native traffic-shift deployments alternate between tg-1
  # and tg-2, rewriting the production listener rule via the
  # infrastructure role.
  dynamic "load_balancer" {
    for_each = local.enable_load_balancer ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.tg_1[0].arn
      container_name   = local.lb_container_name
      container_port   = local.primary_load_balancer_container_port

      dynamic "advanced_configuration" {
        for_each = local.traffic_shift_infrastructure_enabled ? [1] : []
        content {
          alternate_target_group_arn = aws_lb_target_group.tg_2[0].arn
          production_listener_rule = (
            local.enable_nlb_listener
            ? aws_lb_listener.nlb[0].arn
            : aws_lb_listener_rule.alb["0"].arn
          )
          test_listener_rule = local.test_listener_rule_arn
          role_arn           = aws_iam_role.ecs_infrastructure[0].arn
        }
      }
    }
  }

  dynamic "load_balancer" {
    for_each = local.additional_nlb_listeners
    content {
      target_group_arn = aws_lb_target_group.nlb_additional[load_balancer.key].arn
      container_name   = local.lb_container_name
      container_port   = load_balancer.value.container_port
    }
  }

  # Health check grace period
  health_check_grace_period_seconds = local.enable_load_balancer ? var.health_check_grace_period_seconds : null

  # Service discovery
  dynamic "service_registries" {
    for_each = local.enable_service_discovery ? [1] : []
    content {
      registry_arn   = aws_service_discovery_service.this[0].arn
      container_name = local.lb_container_name
      container_port = local.primary_load_balancer_container_port
    }
  }

  # ECS Exec
  enable_execute_command = var.execute_command_enabled

  # Force new deployment
  force_new_deployment = var.new_deployment_forcing_enabled

  # Wait for steady state
  wait_for_steady_state = var.steady_state_wait_enabled

  # Tags
  enable_ecs_managed_tags = var.ecs_managed_tags_enabled
  propagate_tags          = var.propagate_tags

  tags = merge(local.tags, {
    Name = var.name
  })

  # Dependencies
  depends_on = [
    aws_iam_role_policy_attachment.execution_base,
    aws_iam_role_policy_attachment.ecs_infrastructure_elb,
    aws_lb_listener_rule.alb,
    aws_lb_listener_rule.test,
    aws_lb_listener.nlb_additional,
  ]

  # Lifecycle: desired_count is managed by autoscaling, task_definition /
  # Rolling early-success criteria are also owned by the deploy manager:
  # it always sends enabled, defaulting to 100% healthy / DEFERRED cleanup.
  # The provider does not yet expose those fields for create-time configuration.
  # load_balancer / deployment_configuration by the Flightcontrol deploy
  # manager (UpdateService passes the authoritative strategy + pause
  # lifecycle hooks on every deploy, and native traffic-shift deploys
  # alternate the service between the production and alternate target
  # groups), so Terraform must not fight them on subsequent applies.
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition,
      load_balancer,
      deployment_configuration,
    ]

    precondition {
      condition = (
        !local.enable_load_balancer
        || local.enable_nlb_listener
        || length(var.load_balancer_attachment.listener_rules) > 0
      )
      error_message = "load_balancer_attachment requires either listener_rules for ALB or nlb_listeners for NLB."
    }

    # The ECS advanced_configuration API accepts a single production
    # listener rule, so during native traffic-shift deployments only the
    # first rule is rewritten — any additional rules would keep
    # forwarding to the old revision for the entire deployment.
    precondition {
      condition = (
        !local.is_native_traffic_shift
        || local.enable_nlb_listener
        || length(try(var.load_balancer_attachment.listener_rules, [])) <= 1
      )
      error_message = "Native traffic-shift strategies (blue_green/linear/canary) rewrite a single production listener rule; additional listener rules would keep serving the old revision throughout the deployment. Use at most one listener rule with these strategies."
    }

    precondition {
      condition = (
        !local.rolling_nlb_listeners_enabled
        || var.deployment_type == "rolling"
      )
      error_message = "nlb_listeners requires rolling deployments because traffic-shift infrastructure is not created for this shape."
    }
  }
}
