################################################################################
# Cluster Security Group Ingress Extensions
#
# Attaches extra ingress rules to the EKS-managed cluster security group. Useful
# for letting bastion / VPN / on-prem CIDRs reach the cluster API and node
# kubelets without managing a separate SG.
################################################################################

resource "aws_vpc_security_group_ingress_rule" "additional_cidr" {
  for_each = { for idx, rule in var.cluster_security_group_additional_cidr_ingress_rules : idx => rule }

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  cidr_ipv4         = each.value.cidr_ipv4

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "additional_sg" {
  for_each = { for idx, rule in var.cluster_security_group_additional_referenced_security_group_ingress_rules : idx => rule }

  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = each.value.description
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.ip_protocol
  referenced_security_group_id = each.value.referenced_security_group_id

  tags = local.tags
}
