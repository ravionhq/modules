################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/eks_service"
  }

  tags = merge(local.default_tags, var.tags)

  region = coalesce(var.region, data.aws_region.current.region)

  # A listener ARN is what makes this workload web-facing. Worker and cron
  # stacks pass null, and the target group, listener rule, and load balancer
  # lookup all drop out, leaving only the optional ECR repository and Fargate
  # profile. This mirrors compute/ecs_service, where a nullable
  # load_balancer_attachment gates the same objects.
  enable_load_balancer = var.listener_arn != null

  # ELBv2 target group names allow only alphanumerics and hyphens, so the
  # underscores var.name permits (ECR repositories accept them) become hyphens
  # here. The collision hash stays keyed on the raw name so it is stable.
  target_group_base_name = replace(var.name, "_", "-")

  # Preserve short names. Long names include a stable hash so workloads that
  # share a prefix cannot collide within ELBv2's 32-character limit.
  target_group_name = length(var.name) <= 29 ? "${local.target_group_base_name}-tg" : "${substr(local.target_group_base_name, 0, 20)}-${substr(sha1(var.name), 0, 8)}-tg"

  # The health check speaks the same protocol as the target group unless the
  # caller overrides it, which is what ECS does via primary_health_check_protocol.
  health_check_protocol = coalesce(var.target_group_health_check.protocol, var.target_group_protocol)

  # The release teardown needs every piece of the release's identity and the
  # means to reach the cluster; the resource's precondition refuses an apply
  # that enables it without them, rather than a destroy that fails late.
  workload_release_cleanup_enabled = var.workload_release_cleanup_enabled

  # Addresses other workloads use to reach this service. The in-cluster host is
  # the ClusterIP Service the rvn-eks-web chart names after the release, in the
  # release namespace, so it is knowable before the first deploy creates it.
  # Its scheme is the target group protocol, which is what the pods speak. It
  # does not depend on the load balancer: a service can be cluster-only and
  # still be dialled by name. Worker and cron render no Service and leave
  # kubernetes_service_enabled off, so their values are null.
  #
  # The load balancer URL takes its scheme and port from the shared listener
  # and prefers the rule's first concrete host header: a request to the bare
  # ALB hostname would not match a host-scoped rule. Null without a listener.
  service_host = var.kubernetes_service_enabled && var.release_name != null && var.release_namespace != null ? "${var.release_name}.${var.release_namespace}.svc.cluster.local" : null
  service_url  = local.service_host != null ? "${lower(var.target_group_protocol)}://${local.service_host}:${var.container_port}" : null

  load_balancer_host_rules = flatten([
    for condition in var.listener_rule_conditions :
    [for value in condition.values : value if !strcontains(value, "*")]
    if condition.type == "host-header"
  ])
  load_balancer_scheme       = local.enable_load_balancer ? lower(data.aws_lb_listener.attached[0].protocol) : null
  load_balancer_host         = local.enable_load_balancer ? (length(local.load_balancer_host_rules) > 0 ? local.load_balancer_host_rules[0] : data.aws_lb.attached[0].dns_name) : null
  load_balancer_default_port = local.load_balancer_scheme == "https" ? 443 : 80
  load_balancer_port_suffix  = local.enable_load_balancer && data.aws_lb_listener.attached[0].port != local.load_balancer_default_port ? ":${data.aws_lb_listener.attached[0].port}" : ""
  load_balancer_url          = local.enable_load_balancer ? "${local.load_balancer_scheme}://${local.load_balancer_host}${local.load_balancer_port_suffix}" : null
}
