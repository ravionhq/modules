################################################################################
# Auto Scaling Group
#
# One router instance, kept alive. An instance the load balancer reports
# unhealthy is replaced, which is also what retries a boot that failed. A
# replacement is launched before the instance it replaces is drained, so the
# load balancer always has a router that can route.
################################################################################

resource "aws_autoscaling_group" "router" {
  name                = local.router_name
  vpc_zone_identifier = var.router_subnet_ids

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  target_group_arns = [
    aws_lb_target_group.traffic.arn,
    aws_lb_target_group.redirect.arn,
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 180

  # The apply succeeds only once the router answers its health check behind
  # the load balancer, so a router that cannot install or start fails the run
  # that launched it.
  wait_for_elb_capacity     = 1
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.router.id
    version = aws_launch_template.router.latest_version
  }

  # Replacements are launched first: the group may run a second router until
  # the new one is healthy, then drains and terminates the old. A router turns
  # healthy only once it holds its routes, so traffic never reaches one that
  # cannot route.
  instance_maintenance_policy {
    min_healthy_percentage = 100
    max_healthy_percentage = 200
  }

  # The boot script runs once per instance, so a changed launch template takes
  # effect only on a new one, launched before the old one goes.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
    }
  }

  dynamic "tag" {
    for_each = local.router_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Targets of a target group no listener uses are never health checked, and
  # the group waits for a healthy router.
  depends_on = [
    aws_lb_listener.tls,
    aws_lb_listener.http,
  ]
}
