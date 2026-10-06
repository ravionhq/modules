# Only the first deployment needs an apply-time lookup. The branch does not
# exist at plan time yet, and no keyspace import is enabled for this deployment.
data "planetscale_vitess_keyspaces" "initial" {
  count = var.manage_default_keyspace ? 0 : 1

  organization = var.organization
  database     = planetscale_vitess_branch.main.database
  branch       = planetscale_vitess_branch.main.name
}

# Later deployments read the existing branch using its immutable identity.
# Do not depend on the branch resource: changing branch settings must not defer
# this lookup until apply and make the import ID unknown during planning.
data "planetscale_vitess_keyspaces" "main" {
  count = var.manage_default_keyspace ? 1 : 0

  organization = var.organization
  database     = var.name
  branch       = "main"
}
