################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

# The VPC the cluster runs in. The execution environment's sandbox hosts run
# in one of its subnets, so the router reaches them by the VPC's ranges.
data "aws_vpc" "this" {
  id = var.vpc_id
}
