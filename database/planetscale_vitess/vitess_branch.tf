# Stage one targets only this resource. Its automatically provisioned default
# keyspace is imported by the full stage-two plan (see vitess_keyspace.tf).
resource "planetscale_vitess_branch" "main" {
  organization       = var.organization
  database           = var.name
  name               = "main"
  region             = var.region
  cluster_size       = var.cluster_size
  deletion_protected = var.deletion_protection_enabled
  safe_migrations    = var.safe_migrations_enabled
  delete_descendants = false

  vtgate_size                   = var.vtgate.size
  vtgate_count                  = var.vtgate.count
  vtgate_autoscaling            = var.vtgate.autoscaling_enabled
  vtgate_max_count              = var.vtgate.max_count
  vtgate_target_cpu_utilization = var.vtgate.target_cpu_utilization

  lifecycle {
    # The branch attribute is creation-only in the provider. All later sizing
    # belongs to planetscale_vitess_keyspace.main, never branch replacement.
    ignore_changes = [cluster_size]
  }
}
