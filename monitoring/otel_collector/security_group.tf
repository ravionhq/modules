################################################################################
# Security Groups
#
# OTLP is accepted from members of the client security group and from the
# security groups the caller names. Egress is HTTPS alone: X-Ray, CloudWatch,
# Amazon Managed Service for Prometheus and the image registry.
################################################################################

# Senders attach this security group to reach the collector. It carries no
# ingress rules of its own; the collector's security group references it as an
# allowed source.
module "client_security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "otlp-client"
  description = "Client security group granting OTLP access to OpenTelemetry collector ${var.name}"
  vpc_id      = var.vpc_id
  region      = local.region
  tags        = var.tags

  ingress_rules = []

  egress_rules = [
    for port in [local.otlp_grpc_port, local.otlp_http_port] : {
      description                  = "OTLP on ${port} to the collector"
      from_port                    = port
      to_port                      = port
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.security_group.security_group_id
    }
  ]
}

module "security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "collector"
  description = "OTLP ingress for OpenTelemetry collector ${var.name}"
  vpc_id      = var.vpc_id
  region      = local.region
  tags        = var.tags

  ingress_rules = flatten([
    for source in concat([module.client_security_group.security_group_id], var.allowed_security_group_ids) : [
      for port in [local.otlp_grpc_port, local.otlp_http_port] : {
        description                  = "OTLP on ${port} from ${source}"
        from_port                    = port
        to_port                      = port
        ip_protocol                  = "tcp"
        referenced_security_group_id = source
      }
    ]
  ])

  egress_rules = [{
    description = "HTTPS to AWS APIs and the image registry"
    from_port   = 443
    to_port     = 443
    ip_protocol = "tcp"
    cidr_ipv4   = "0.0.0.0/0"
  }]
}
