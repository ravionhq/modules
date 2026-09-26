output "engine" {
  description = "PlanetScale database engine."
  value       = "vitess"
}

output "organization" {
  description = "PlanetScale organization slug."
  value       = var.organization
}

output "database" {
  description = "PlanetScale database name."
  value       = planetscale_vitess_branch.main.database
}

output "branch" {
  description = "Main branch name."
  value       = planetscale_vitess_branch.main.name
}

output "branch_id" {
  description = "Main branch ID."
  value       = planetscale_vitess_branch.main.id
}

output "keyspace" {
  description = "Default keyspace name, discovered from PlanetScale."
  value       = planetscale_vitess_keyspace.main.name
}

output "cluster_size" {
  description = "Managed main-keyspace cluster size."
  value       = planetscale_vitess_keyspace.main.cluster_size
}

output "host" {
  description = "Application credential's MySQL connection host."
  value       = planetscale_vitess_branch_password.application.access_host_url
}

output "port" {
  description = "MySQL TLS connection port."
  value       = 3306
}

output "database_name" {
  description = "Database name to pass to the MySQL driver."
  value       = var.name
}

output "username" {
  description = "Generated application username."
  value       = planetscale_vitess_branch_password.application.username
}

output "password" {
  description = "Generated application password; stored in Terraform state."
  value       = planetscale_vitess_branch_password.application.plain_text
  sensitive   = true
}

output "connection_string" {
  description = "MySQL URI with escaped credentials. Configure TLS certificate and hostname verification in your driver's options."
  value       = local.connection_string
  sensitive   = true
}

output "tls_required" {
  description = "Clients must use TLS with certificate and hostname verification."
  value       = true
}

output "dashboard_url" {
  description = "PlanetScale main branch dashboard."
  value       = planetscale_vitess_branch.main.html_url
}

output "additional_credentials" {
  description = "Additional credentials keyed by their configured names. Passwords are stored in Terraform state."
  sensitive   = true
  value = {
    for name, password in planetscale_vitess_branch_password.additional : name => {
      host     = password.access_host_url
      port     = 3306
      username = password.username
      password = password.plain_text
      database = var.name
    }
  }
}
