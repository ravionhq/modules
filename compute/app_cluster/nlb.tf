################################################################################
# Network Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.load_balancer.id]

  # One router instance serves every zone the load balancer answers in.
  enable_cross_zone_load_balancing = true

  tags = merge(local.tags, {
    Name = var.name
  })
}
