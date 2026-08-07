################################################################################
# Security Group
################################################################################

module "security_group" {
  count = local.create_security_group ? 1 : 0

  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "rds"
  description = "Security group for ${var.name} RDS instance"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress_rules = concat(
    # Security group sources
    [
      for sg_id in var.allowed_security_group_ids : {
        description                  = "Allow ${var.engine} traffic from ${sg_id}"
        from_port                    = local.port
        to_port                      = local.port
        ip_protocol                  = "tcp"
        referenced_security_group_id = sg_id
      }
    ],
    # IPv4 CIDR sources
    [
      for cidr in var.allowed_cidr_blocks : {
        description = "Allow ${var.engine} traffic from ${cidr}"
        from_port   = local.port
        to_port     = local.port
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ],
    # RDS Proxy source
    local.create_proxy ? [
      {
        description                  = "Allow ${var.engine} traffic from the RDS Proxy"
        from_port                    = local.port
        to_port                      = local.port
        ip_protocol                  = "tcp"
        referenced_security_group_id = module.proxy[0].security_group_id
      }
    ] : []
  )

  # Egress to VPC only. For ip_protocol="-1" (all protocols), AWS requires
  # from_port/to_port to be omitted; use -1 here for caller clarity.
  egress_rules = [
    {
      description = "Allow outbound traffic within VPC"
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.this.cidr_block
    }
  ]
}
