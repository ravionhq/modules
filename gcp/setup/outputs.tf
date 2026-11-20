output "setup_version" {
  description = "Ravion setup version installed in the project."
  value       = local.setup_version
}

output "project_number" {
  description = "Project number (used in the workload identity provider name)."
  value       = data.google_project.this.number
}

output "workload_identity_provider" {
  description = "Full resource name of the workload identity provider Ravion exchanges tokens with."
  value       = google_iam_workload_identity_pool_provider.ravion.name
}

output "service_accounts" {
  description = "Service accounts Ravion impersonates, by tier."
  value       = { for name, sa in google_service_account.tier : name => sa.email }
}

output "attached_service_accounts" {
  description = "Service accounts Ravion attaches to the VMs it creates."
  value       = { for name, sa in google_service_account.attached : name => sa.email }
}
