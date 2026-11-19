################################################################################
# Data Sources
################################################################################

# Endpoint and CA for the existing cluster Temporal is installed onto.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# The VPC's CIDR, admitted by the network policies when a load balancer sends
# traffic from addresses inside the VPC: the Web UI ingress, and the frontend
# NLB's health checks when its subnets are discovered rather than listed.
data "aws_vpc" "cluster" {
  count = local.web_ingress_vpc_cidr_needed ? 1 : 0

  id = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

# The frontend NLB's subnets, whose addresses its health checks come from.
data "aws_subnet" "frontend_nlb" {
  for_each = var.frontend_nlb_enabled && var.network_policy_enabled ? toset(var.frontend_nlb_subnet_ids) : toset([])

  id = each.value
}

# The frontend NLB the load balancer controller creates, read once the release
# that asks for it is in place (Helm waits for the Service's address).
data "aws_lb" "frontend" {
  count = var.frontend_nlb_enabled ? 1 : 0

  name = local.frontend_nlb_name

  depends_on = [helm_release.temporal_resources]
}

# The Aurora cluster holding Temporal's persistence and visibility databases.
# Its endpoint, port and master username come from here, and its engine is
# checked before anything is installed.
data "aws_rds_cluster" "database" {
  cluster_identifier = var.database_cluster_identifier
}
