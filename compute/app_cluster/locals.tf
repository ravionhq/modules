locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/app_cluster"
  }
  tags = merge(local.default_tags, var.tags)

  router_name = "${var.name}-router"
  hosts_name  = "${var.name}-hosts"

  # Ravion may pass only roles named rvn-app-router-* to the router instance
  # it launches.
  router_role_name = "rvn-app-router-${var.name}"

  # Ravion launches the router with this tag and may register targets only in
  # target groups that carry it.
  router_tag_key = "ravion:app-router"

  # Ports the router listens on. The load balancer terminates TLS and hands
  # the router plain TCP.
  router_ports = {
    traffic  = 8080 # app requests, from the TLS listener
    redirect = 8081 # plain HTTP, answered with a redirect to HTTPS
    health   = 8082 # /healthz, for the load balancer's health checks
  }
  router_port_purposes = {
    traffic  = "app traffic"
    redirect = "HTTP redirects"
    health   = "health checks"
  }

  # Host ports a sandbox host serves an app's ports on, its own health port
  # (the last one) included. The router reaches the hosts on these and nothing
  # else.
  app_port_range = {
    from = 20000
    to   = 20999
  }

  # Target group names share ELBv2's 32-character limit with the load
  # balancer. Short names stay readable; long names keep a stable hash.
  target_group_name_prefix = length(var.name) <= 26 ? var.name : "${substr(var.name, 0, 17)}-${substr(sha1(var.name), 0, 8)}"

  # AWS APIs are always HTTPS on 443. A control plane on another port needs
  # that port as well.
  ravion_api_port    = try(tonumber(regex(":([0-9]+)$", var.ravion_api_url)[0]), 443)
  router_https_ports = toset([for port in [443, local.ravion_api_port] : tostring(port)])
}
