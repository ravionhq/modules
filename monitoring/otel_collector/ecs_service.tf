################################################################################
# ECS Service
################################################################################

resource "aws_ecs_service" "this" {
  name             = var.name
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [module.security_group.security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
  }

  # A configuration the collector cannot start with rolls back to the last
  # revision that ran, and the apply waits so it fails rather than reporting
  # success over a crash-looping service.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = true

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = local.tags
}
