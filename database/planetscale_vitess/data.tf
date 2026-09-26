data "planetscale_vitess_keyspaces" "main" {
  organization = var.organization
  database     = planetscale_vitess_branch.main.database
  branch       = planetscale_vitess_branch.main.name
}
