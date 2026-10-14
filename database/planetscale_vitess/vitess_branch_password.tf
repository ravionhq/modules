resource "planetscale_vitess_branch_password" "application" {
  organization = var.organization
  database     = planetscale_vitess_branch.main.database
  branch       = planetscale_vitess_branch.main.name
  name         = var.application_password.name
  role         = var.application_password.role
  cidrs        = var.application_password.cidrs
}

resource "planetscale_vitess_branch_password" "additional" {
  for_each = var.additional_passwords

  organization  = var.organization
  database      = planetscale_vitess_branch.main.database
  branch        = planetscale_vitess_branch.main.name
  name          = each.key
  role          = each.value.role
  cidrs         = each.value.cidrs
  replica       = each.value.replica_enabled
  direct_vtgate = each.value.direct_vtgate_enabled
  ttl           = each.value.ttl
}
