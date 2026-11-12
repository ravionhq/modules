################################################################################
# Data Sources
################################################################################

# Endpoint and CA for the existing cluster Temporal is installed onto.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# The VPC's CIDR, admitted to the Web UI when an ingress sends traffic from
# load balancer addresses inside the VPC.
data "aws_vpc" "cluster" {
  count = local.web_ingress_vpc_cidr_needed ? 1 : 0

  id = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

# The Aurora cluster holding Temporal's persistence and visibility databases.
# Its endpoint, port and master username come from here, and its engine is
# checked before anything is installed.
data "aws_rds_cluster" "database" {
  cluster_identifier = var.database_cluster_identifier
}
