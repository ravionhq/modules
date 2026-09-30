################################################################################
# VPC connection
#
# Once connected, every query the workspace makes leaves from the VPC, the AWS
# data sources included. The workspace's own security group lets HTTPS out so
# it still reaches X-Ray, CloudWatch, and Prometheus through a NAT gateway or
# VPC endpoints; groups passed in, such as a Loki client group, sit beside it.
################################################################################

module "security_group" {
  count = local.vpc_enabled ? 1 : 0

  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "grafana"
  description = "VPC connection of Amazon Managed Grafana workspace ${var.name}"
  vpc_id      = var.vpc_id
  region      = local.region
  tags        = local.tags

  ingress_rules = []

  egress_rules = [{
    description = "HTTPS to AWS data sources"
    from_port   = 443
    to_port     = 443
    ip_protocol = "tcp"
    cidr_ipv4   = "0.0.0.0/0"
  }]
}
