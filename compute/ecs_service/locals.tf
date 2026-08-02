locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ecs_service"
  }

  tags = merge(local.default_tags, var.tags)

  # Every strategy runs on the native ECS deployment controller — the
  # blue_green / linear / canary traffic shifts are executed by ECS
  # itself (deployment_configuration.strategy), not CodeDeploy.
  deployment_controller_type = "ECS"

  # Strategies that run the ECS controller's traffic-shift state machine
  # over two target groups (production + alternate). Only used to seed
  # deployment_configuration at create time — the target-group pair,
  # infrastructure role, and advanced_configuration are provisioned for
  # every load-balanced service so the strategy can change per
  # deployment without Terraform changes.
  is_native_traffic_shift = contains(["blue_green", "linear", "canary"], var.deployment_type)

  # Map the module's strategy name to the AWS deploymentConfiguration enum.
  deployment_strategy = {
    rolling    = "ROLLING"
    blue_green = "BLUE_GREEN"
    linear     = "LINEAR"
    canary     = "CANARY"
  }[var.deployment_type]

  # Determine if load balancer is configured
  enable_load_balancer = var.load_balancer_attachment != null && var.load_balancer_attachment.enabled

  # Determine if NLB listeners should be created (vs ALB listener rules).
  enable_nlb_listener = local.enable_load_balancer && length(try(var.load_balancer_attachment.nlb_listeners, [])) > 0

  rolling_nlb_listeners_enabled        = local.enable_load_balancer && length(try(var.load_balancer_attachment.nlb_listeners, [])) > 0
  traffic_shift_infrastructure_enabled = local.enable_load_balancer && !local.rolling_nlb_listeners_enabled

  # Determine if a dedicated test (green) ALB listener rule should be
  # created. Drives the advanced_configuration.test_listener_rule wiring
  # and the TEST_TRAFFIC_SHIFT lifecycle stages on native traffic-shift
  # deploys. ALB-only — requires a production listener rule to mirror; a
  # no-op for NLB services. Suppressed for Ravion-managed services: the
  # mirrored conditions come from caller listener_rules, which managed
  # mode discards in favour of the module-created host-header rules, so
  # the test rule would orphan on the caller's listener.
  green_alb_listener_rule_enabled = (
    local.enable_load_balancer
    && !local.enable_nlb_listener
    && !local.ravion_managed
    && var.green_alb_listener_rule_enabled
    && length(var.load_balancer_attachment.listener_rules) > 0
  )

  # When the green rule is enabled the module owns both priorities so the
  # test rule (production conditions + the configured test selector) is always
  # evaluated before the production rule — otherwise ALB, which routes by
  # priority order and not specificity, would match production first and a
  # test request would never reach green. The production rule's
  # priority becomes the base (its configured priority, else the default
  # below) and the test rule sits one slot ahead at base - 1. Both numbers
  # must be unique across all rules on a shared listener; set an explicit
  # Listener rule priority per service when several green services share a
  # listener.
  green_default_production_priority = 1000
  green_production_priority = local.green_alb_listener_rule_enabled ? coalesce(
    var.load_balancer_attachment.listener_rules[0].priority,
    local.green_default_production_priority,
  ) : null
  green_test_priority = local.green_alb_listener_rule_enabled ? local.green_production_priority - 1 : null

  # ARN passed to advanced_configuration.test_listener_rule and exported:
  # the module-created rule when configured, else an externally-managed
  # rule ARN supplied by the caller, else null.
  test_listener_rule_arn = local.green_alb_listener_rule_enabled ? aws_lb_listener_rule.test[0].arn : var.test_listener_rule_arn

  # ALB rules whose forward action ECS rewrites during native
  # traffic-shift deployments must carry group-level stickiness when the
  # target groups have target-level stickiness: ELBv2 rejects a
  # multi-target-group forward referencing a sticky target group unless
  # the action itself has TargetGroupStickinessConfig enabled ("You must
  # enable group stickiness on a rule if you enabled target stickiness
  # on one of its target groups"), which fails the deployment's
  # PRE_SCALE_UP stage. ALB-only — NLB listeners forward to one target
  # group at a time.
  alb_group_stickiness_enabled = (
    local.enable_load_balancer
    && !local.enable_nlb_listener
    && var.load_balancer_attachment.target_group.stickiness != null
    && var.load_balancer_attachment.target_group.stickiness.enabled
  )
  # Reuse the target-group cookie duration so a client pinned to the
  # blue or green group stays pinned for the same window as its
  # in-group target pinning.
  alb_group_stickiness_duration = local.alb_group_stickiness_enabled ? var.load_balancer_attachment.target_group.stickiness.cookie_duration : null

  # Placeholder container name and port
  placeholder_container_name = "app"
  placeholder_container_port = var.container_port

  # Container name and port for load balancer
  lb_container_name = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_name,
    local.placeholder_container_name
  ) : local.placeholder_container_name

  lb_container_port = local.enable_load_balancer ? coalesce(
    var.load_balancer_attachment.container_port,
    local.placeholder_container_port
  ) : null

  nlb_listeners = local.enable_nlb_listener ? var.load_balancer_attachment.nlb_listeners : []

  primary_nlb_listener = local.enable_nlb_listener ? local.nlb_listeners[0] : null
  primary_target_group_port = local.enable_nlb_listener ? (
    local.primary_nlb_listener.container_port
  ) : try(var.load_balancer_attachment.target_group.port, null)
  primary_target_group_protocol = local.enable_nlb_listener ? (
    local.primary_nlb_listener.target_protocol
  ) : try(var.load_balancer_attachment.target_group.protocol, null)
  primary_health_check_protocol = local.enable_load_balancer ? coalesce(
    try(var.load_balancer_attachment.target_group.health_check.protocol, null),
    contains(["TLS", "UDP"], local.primary_target_group_protocol) ? "TCP" : local.primary_target_group_protocol,
  ) : null
  primary_load_balancer_container_port = local.enable_nlb_listener ? (
    local.primary_nlb_listener.container_port
  ) : local.lb_container_port
  additional_nlb_listeners = {
    for index, listener in local.nlb_listeners : tostring(listener.port) => listener
    if index > 0
  }
  additional_nlb_health_check_protocols = {
    for port, listener in local.additional_nlb_listeners : port => coalesce(
      try(var.load_balancer_attachment.target_group.health_check.protocol, null),
      contains(["TLS", "UDP"], listener.target_protocol) ? "TCP" : listener.target_protocol,
    )
  }

  load_balancer_port_mappings = local.enable_nlb_listener ? [
    for listener in local.nlb_listeners : {
      container_port = listener.container_port
      protocol       = listener.protocol == "UDP" ? "udp" : "tcp"
    }
    ] : local.enable_load_balancer ? [
    {
      container_port = local.lb_container_port
      protocol       = "tcp"
    }
    ] : [
    {
      container_port = local.placeholder_container_port
      protocol       = "tcp"
    }
  ]

  # Determine if we need to create IAM roles
  create_execution_role = var.execution_role_arn == null
  create_task_role      = var.task_role_arn == null


  # Hardcoded placeholder container definition - the external deployment controller will replace with the actual application
  container_definitions = jsonencode([
    {
      name      = local.placeholder_container_name
      image     = "public.ecr.aws/docker/library/hello-world:latest"
      essential = true
      cpu       = 0
      memory    = null

      stopTimeout = 30

      portMappings = [
        for mapping in local.load_balancer_port_mappings : {
          containerPort = tonumber(mapping.container_port)
          hostPort      = var.network_mode == "awsvpc" ? tonumber(mapping.container_port) : null
          protocol      = mapping.protocol
          name          = null
          appProtocol   = null
        }
      ]

      environment = []
      secrets     = []
      healthCheck = null

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.name}"
          awslogs-region        = local.region
          awslogs-stream-prefix = local.placeholder_container_name
          awslogs-create-group  = "true"
        }
        secretOptions = []
      }

      mountPoints            = []
      volumesFrom            = []
      dependsOn              = []
      command                = null
      entryPoint             = null
      workingDirectory       = null
      readonlyRootFilesystem = false
      privileged             = false
      user                   = null
      ulimits                = []
      systemControls         = []
      linuxParameters = {
        initProcessEnabled = true
        capabilities       = null
        devices            = []
        maxSwap            = null
        sharedMemorySize   = null
        swappiness         = null
        tmpfs              = []
      }
      dockerLabels = null
    }
  ])

  # Auto scaling settings
  auto_scaling_enabled = var.auto_scaling != null && var.auto_scaling.enabled

  # Service discovery settings
  enable_service_discovery = var.service_discovery != null
}
