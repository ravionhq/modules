################################################################################
# Ravion Runner Security Group
#
# Created by default so Ravion Runner instances (e.g. the Helm steps of the
# compute/eks/addons stack) can reach the private Kubernetes API endpoint.
# Attach this security group to the Ravion execution environment used by
# modules that talk to the cluster's Kubernetes API.
# The EKS-managed cluster security group only admits the cluster's own nodes
# and ENIs, so the runner needs an explicit 443 ingress rule.
################################################################################

resource "aws_security_group" "ravion_runner" {
  count = var.ravion_runner_security_group_creation_enabled ? 1 : 0

  name        = "${var.name}-ravion-runner"
  description = "Ravion Runner access to the ${var.name} EKS cluster API endpoint"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-ravion-runner"
  })
}

resource "aws_vpc_security_group_egress_rule" "ravion_runner_all" {
  count = var.ravion_runner_security_group_creation_enabled ? 1 : 0

  security_group_id = aws_security_group.ravion_runner[0].id
  description       = "Ravion Runner outbound access"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_ravion_runner" {
  count = var.ravion_runner_security_group_creation_enabled ? 1 : 0

  security_group_id            = module.cluster.cluster_security_group_id
  description                  = "Ravion Runner"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ravion_runner[0].id

  tags = local.tags
}
