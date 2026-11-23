output "project_id" {
  description = "The Google Cloud project ID."
  value       = var.project_id
}

output "region" {
  description = "The region of the load balancer."
  value       = var.region
}

output "ip_address" {
  description = "IP address clients connect to."
  value       = google_compute_forwarding_rule.this.ip_address
}

output "ip_address_self_link" {
  description = "Self link of the reserved address (null when ip_address_creation_enabled is false)."
  value       = var.ip_address_creation_enabled ? google_compute_address.this[0].self_link : null
}

output "forwarding_rule_id" {
  description = "ID of the forwarding rule."
  value       = google_compute_forwarding_rule.this.id
}

output "forwarding_rule_self_link" {
  description = "Self link of the forwarding rule."
  value       = google_compute_forwarding_rule.this.self_link
}

output "backend_service_id" {
  description = "ID of the regional backend service."
  value       = google_compute_region_backend_service.this.id
}

output "backend_service_self_link" {
  description = "Self link of the regional backend service."
  value       = google_compute_region_backend_service.this.self_link
}

output "health_check_id" {
  description = "ID of the regional health check."
  value       = google_compute_region_health_check.this.id
}

output "firewall_rule_names" {
  description = "Names of the firewall rules created for health checks and clients."
  value       = concat(google_compute_firewall.health_checks[*].name, google_compute_firewall.clients[*].name)
}
