# The native aws_eks_node_group data source fails for a group that does not yet
# exist, and cannot find one whose name is generated. This read-only lookup
# handles first creation without a plan-time count or a resource dependency
# cycle, and finds the live group by its ravion.com/node-group tag (or, for a
# group created before names were generated, by its exact name). Mutations
# remain owned by the AWS provider.
data "external" "scaling" {
  program = ["python3", "${path.module}/scripts/read_scaling.py"]
  query = {
    cluster_name    = var.cluster_name
    node_group_name = var.name
    region          = data.aws_region.current.region
    account_id      = data.aws_caller_identity.current.account_id
  }
}

locals {
  current_desired_size = data.external.scaling.result.exists == "true" ? tonumber(data.external.scaling.result.desired_size) : var.desired_size
}
