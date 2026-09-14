################################################################################
# Service Discovery Namespace
#
# One Cloud Map private DNS namespace per cluster. ECS web and network services
# register a Cloud Map service in it, so a task in the VPC resolves
# <service name>.<namespace> straight to the peer's task IPs with no load
# balancer hop. The namespace owns a Route 53 private hosted zone associated
# with the cluster VPC, which needs DNS support and DNS hostnames enabled.
################################################################################

resource "aws_service_discovery_private_dns_namespace" "this" {
  count = var.service_discovery_namespace_enabled ? 1 : 0

  name        = local.service_discovery_namespace_name
  vpc         = var.vpc_id
  description = "Service discovery namespace for ECS cluster ${var.name}"

  tags = merge(local.tags, {
    Name = local.service_discovery_namespace_name
  })
}
