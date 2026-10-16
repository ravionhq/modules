resource "planetscale_vitess_backup_policy" "additional" {
  for_each = var.backup_policies

  organization    = var.organization
  database        = planetscale_vitess_branch.main.database
  name            = each.key
  target          = each.value.target
  frequency_unit  = each.value.frequency_unit
  frequency_value = each.value.frequency_value
  retention_unit  = each.value.retention_unit
  retention_value = each.value.retention_value
  schedule_time   = each.value.schedule_time
  schedule_day    = each.value.schedule_day
  schedule_week   = each.value.schedule_week
}
