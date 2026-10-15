# The first ordinary apply creates the branch and its default keyspace. Later
# applies automatically import that existing keyspace and can resize it in the
# same apply. Once imported, this block is a no-op.
import {
  for_each = var.manage_default_keyspace ? { main = true } : {}
  to       = planetscale_vitess_keyspace.main[0]
  id = jsonencode({
    organization = var.organization
    database     = var.name
    branch       = "main"
    name         = local.default_keyspace_name
  })
}

# Preserve state addresses from the previous two-stage module.
moved {
  from = planetscale_vitess_keyspace.main
  to   = planetscale_vitess_keyspace.main[0]
}

resource "planetscale_vitess_keyspace" "main" {
  count = var.manage_default_keyspace ? 1 : 0

  organization   = var.organization
  database       = planetscale_vitess_branch.main.database
  branch         = planetscale_vitess_branch.main.name
  name           = local.default_keyspace_name
  cluster_size   = var.cluster_size
  extra_replicas = var.extra_replicas

  lifecycle {
    precondition {
      condition     = local.default_keyspace_name != null
      error_message = "The existing branch must have exactly one default keyspace. Enable management only after the first deployment has created the branch."
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
