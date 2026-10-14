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
    Module    = "networking/preview_ingress"
  }
  tags = merge(local.default_tags, var.tags)

  router_name = "${var.name}-router"

  # Ravion enrolls a router only when its instance carries this tag with the
  # module instance id the router names, so the tag is what ties the instance
  # to this module instance.
  router_tags = merge(local.tags, {
    Name                    = local.router_name
    "ravion:preview-router" = var.module_instance_id
  })

  # Ports the router listens on. The load balancer terminates TLS and hands
  # the router plain TCP.
  router_ports = {
    traffic  = 8080 # preview requests, from the TLS listener
    redirect = 8081 # plain HTTP, answered with a redirect to HTTPS
    health   = 8082 # /healthz, for the load balancer's health checks
  }
  router_port_purposes = {
    traffic  = "preview traffic"
    redirect = "HTTP redirects"
    health   = "health checks"
  }

  # Ports sandbox hosts publish previews on. The router forwards nowhere else.
  preview_port_range = {
    from = 20000
    to   = 20998
  }

  # Target group names share ELBv2's 32-character limit with the load
  # balancer. Short names stay readable; long names keep a stable hash.
  target_group_name_prefix = length(var.name) <= 26 ? var.name : "${substr(var.name, 0, 17)}-${substr(sha1(var.name), 0, 8)}"

  vpc_cidr_blocks = [
    for association in data.aws_vpc.this.cidr_block_associations : association.cidr_block
    if association.state == "associated"
  ]

  # AWS APIs are always HTTPS on 443. A control plane on another port needs
  # that port as well.
  ravion_api_port    = try(tonumber(regex(":([0-9]+)$", var.ravion_api_url)[0]), 443)
  router_https_ports = toset([for port in [443, local.ravion_api_port] : tostring(port)])

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    ravion_api_url     = var.ravion_api_url
    module_instance_id = var.module_instance_id
    router_ports       = local.router_ports
  })
}
