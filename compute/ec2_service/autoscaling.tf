################################################################################
# Auto Scaling Group
################################################################################

module "autoscaling" {
  source = "../autoscaling"

  name                = var.name
  name_prefix         = var.autoscaling_group_generated_name_enabled ? "${var.name}-" : null
  vpc_zone_identifier = var.subnet_ids

  # Capacity
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Health checks. EC2 by default: in-place deploys briefly deregister
  # instances from the target group, which ELB health checks would treat
  # as unhealthy and replace mid-deploy.
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Use existing launch template (don't create new one)
  launch_template_creation_enabled = false
  launch_template_id               = aws_launch_template.app.id
  launch_template_version          = "$Latest"

  # Register instances with the service target group
  target_group_arns = local.load_balancer_creation_enabled ? [aws_lb_target_group.app[0].arn] : []

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
  ]

  # Visibility-only lifecycle hooks: they emit "EC2 Instance-launch/-terminate
  # Lifecycle Action" EventBridge events that Ravion ingests to show instances
  # while they are still Pending/Terminating. Nothing completes the action, so
  # the minimum 30s heartbeat with CONTINUE keeps the added launch/terminate
  # delay as small as possible.
  lifecycle_hooks = [
    {
      name                 = "ravion-launch-visibility"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 30
    },
    {
      name                 = "ravion-terminate-visibility"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 30
    },
  ]

  scaling_policies = var.cpu_autoscaling_enabled ? [
    {
      name        = "${var.name}-cpu-target-tracking"
      policy_type = "TargetTrackingScaling"

      target_tracking_configuration = {
        target_value = var.cpu_target_value
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    }
  ] : []

  tags = merge(local.tags, {
    Name = var.name
  })
}
