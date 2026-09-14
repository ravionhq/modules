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
    Module    = "compute/ecs_cluster"
  }

  tags = merge(local.default_tags, var.tags)

  # Determine if EC2 capacity provider should be created
  enable_ec2 = var.ec2_instance_type != null

  # Cluster name
  cluster_name = var.name

  # Private DNS suffix services register under. The cluster name cannot hold a
  # dot, so the default appends one label to it.
  service_discovery_namespace_name = coalesce(var.service_discovery_namespace_name, "${var.name}.internal")

  # EC2 capacity provider name
  ec2_capacity_provider_name = local.enable_ec2 ? "${var.name}-ec2" : null

  # Family used for the cluster default strategy. AWS rejects default
  # strategies that mix Fargate and EC2 (ASG) capacity providers, so the
  # default strategy must commit to a single family.
  capacity_provider_default = coalesce(
    var.capacity_provider_default,
    local.enable_ec2 ? "ec2" : var.fargate_enabled ? "fargate" : "fargate_spot"
  )

  # Build the default capacity provider strategy from the selected family.
  # FARGATE and FARGATE_SPOT may share a strategy; EC2 must stand alone.
  capacity_provider_strategy = local.capacity_provider_default == "ec2" ? [{
    capacity_provider = aws_ecs_capacity_provider.ec2[0].name
    weight            = var.ec2_weight
    base              = var.ec2_base
    }] : concat(
    local.capacity_provider_default == "fargate" && var.fargate_enabled ? [{
      capacity_provider = "FARGATE"
      weight            = var.fargate_weight
      base              = var.fargate_base
    }] : [],
    var.fargate_spot_enabled ? [{
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
      base              = var.fargate_spot_base
    }] : []
  )

  # User data script for ECS EC2 instances
  ecs_user_data = local.enable_ec2 ? base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
    ${var.ec2_user_data}
  EOF
  ) : null

  # Instance types for mixed instances policy
  ec2_instance_types = local.enable_ec2 ? concat(
    [var.ec2_instance_type],
    var.ec2_spot_instance_types
  ) : []
}
