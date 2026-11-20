output "name" {
  description = "Name prefix of the builder VMs and images each deploy creates."
  value       = var.name
}

output "project_id" {
  description = "Project images are built and stored in."
  value       = var.project_id
}

output "region" {
  description = "Region of the component bucket."
  value       = var.region
}

output "zone" {
  description = "Zone the builder and test VMs run in."
  value       = local.zone
}

output "labels" {
  description = "Labels every image a deploy creates carries, already in label syntax."
  value       = local.labels
}

output "builder_service_account_email" {
  description = "Email of the service account the builder and test VMs run as."
  value       = google_service_account.builder.email
}

output "component_bucket" {
  description = "Name of the bucket holding the component scripts."
  value       = google_storage_bucket.components.name
}

output "component_refs" {
  description = "Every component in run order, as {name, url, generation, sha256, parameters}. A build downloads url at generation and checks sha256; parameters are the values each deploy passes unless it overrides them."
  value = [
    for c in var.components : {
      name       = c.name
      url        = "gs://${google_storage_bucket.components.name}/${google_storage_bucket_object.components[c.name].name}"
      generation = google_storage_bucket_object.components[c.name].generation
      sha256     = local.component_objects[c.name].sha256
      parameters = {
        for p in c.parameter_definitions : p.name => p.value
        if try(trimspace(p.value), "") != ""
      }
    }
  ]
}

output "network_self_link" {
  description = "Self link of the network the builder and test VMs attach to."
  value       = var.subnetwork == null ? data.google_compute_network.this[0].self_link : data.google_compute_subnetwork.this[0].network
}

output "subnetwork_self_link" {
  description = "Self link of the subnetwork the builder and test VMs attach to, or null for an auto mode network's own subnetwork."
  value       = var.subnetwork == null ? null : data.google_compute_subnetwork.this[0].self_link
}

output "module_instance_id" {
  description = "Id of the Ravion module instance these resources belong to, for a reference that names this module."
  value       = var.module_instance_id
}
