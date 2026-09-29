################################################################################
# Collector Security Group
#
# OTLP is accepted only from the security groups the caller names. Egress is
# HTTPS alone: X-Ray, CloudWatch Logs and the image registry.
################################################################################

module "security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "collector"
  description = "OTLP ingress for OpenTelemetry collector ${var.name}"
  vpc_id      = var.vpc_id
  region      = local.region
  tags        = var.tags

  ingress_rules = flatten([
    for security_group_id in var.allowed_security_group_ids : [
      for port in [local.otlp_grpc_port, local.otlp_http_port] : {
        description                  = "OTLP on ${port} from ${security_group_id}"
        from_port                    = port
        to_port                      = port
        ip_protocol                  = "tcp"
        referenced_security_group_id = security_group_id
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
