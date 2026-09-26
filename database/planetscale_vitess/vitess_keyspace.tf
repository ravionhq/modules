# Imports run at plan time, after the branch bootstrap has been applied. Once
# imported, this block is a no-op on subsequent plans and can remain in config.
import {
  to = planetscale_vitess_keyspace.main
  id = jsonencode({
    organization = var.organization
    database     = var.name
    branch       = planetscale_vitess_branch.main.name
    name         = local.default_keyspace_name
  })
}

resource "planetscale_vitess_keyspace" "main" {
  organization   = var.organization
  database       = planetscale_vitess_branch.main.database
  branch         = planetscale_vitess_branch.main.name
  name           = local.default_keyspace_name
  cluster_size   = var.cluster_size
  extra_replicas = var.extra_replicas

  lifecycle {
    precondition {
      condition     = local.default_keyspace_name != null
      error_message = "The branch must have exactly one default keyspace. Complete the branch bootstrap before the full plan."
    }
  }
}

resource "planetscale_vitess_keyspace" "additional" {
  for_each = var.additional_keyspaces

  organization   = var.organization
  database       = planetscale_vitess_branch.main.database
  branch         = planetscale_vitess_branch.main.name
  name           = each.key
  cluster_size   = each.value.cluster_size
  extra_replicas = each.value.extra_replicas
  shards         = each.value.shards

  lifecycle {
    precondition {
      condition     = each.key != local.default_keyspace_name
      error_message = "The default keyspace is already managed by the module; additional_keyspaces must use different names."
    }
  }
}
