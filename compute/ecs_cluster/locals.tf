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

################################################################################
# Load Balancer Names
################################################################################

locals {
  public_alb_names  = [for idx, lb in var.public_albs : coalesce(lb.name, idx == 0 ? "${var.name}-pub" : "${var.name}-pub-${idx + 1}")]
  private_alb_names = [for idx, lb in var.private_albs : coalesce(lb.name, idx == 0 ? "${var.name}-priv" : "${var.name}-priv-${idx + 1}")]
  public_nlb_names  = [for idx, lb in var.public_nlbs : coalesce(lb.name, idx == 0 ? "${var.name}-pub-nlb" : "${var.name}-pub-nlb-${idx + 1}")]
  private_nlb_names = [for idx, lb in var.private_nlbs : coalesce(lb.name, idx == 0 ? "${var.name}-priv-nlb" : "${var.name}-priv-nlb-${idx + 1}")]

  # Load balancer configs keyed by resolved name so Terraform addresses stay
  # stable when entries are inserted, removed, or reordered.
  public_albs_by_name  = { for idx, lb in var.public_albs : local.public_alb_names[idx] => lb }
  private_albs_by_name = { for idx, lb in var.private_albs : local.private_alb_names[idx] => lb }
  public_nlbs_by_name  = { for idx, lb in var.public_nlbs : local.public_nlb_names[idx] => lb }
  private_nlbs_by_name = { for idx, lb in var.private_nlbs : local.private_nlb_names[idx] => lb }
}
