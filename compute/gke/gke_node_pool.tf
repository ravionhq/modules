################################################################################
# Node pools
#
# The system pool and every additional pool. Node counts are totals across the
# cluster's zones, and the cluster autoscaler owns the running count, so
# Terraform only sets the bounds.
#
# A name prefix and create_before_destroy let a change GKE can only make by
# recreating the pool (machine type, Spot, disk) bring up the new pool before
# the old one is drained and deleted.
################################################################################

resource "google_container_node_pool" "this" {
  for_each = local.node_pools

  name_prefix = "${each.key}-"
  project     = var.project_id
  location    = var.region
  cluster     = google_container_cluster.this.name

  # Per zone. Starting at one node per zone lets the autoscaler settle on the
  # total bounds below instead of every pool starting empty.
  initial_node_count = each.value.min_nodes > 0 ? 1 : 0

  autoscaling {
    total_min_node_count = each.value.min_nodes
    total_max_node_count = each.value.max_nodes
    # ANY lets Spot pools move to whichever zone has capacity.
    location_policy = each.value.capacity_type == "SPOT" ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    spot            = each.value.capacity_type == "SPOT"
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    service_account = local.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = each.value.labels
    resource_labels = local.labels

    metadata = {
      disable-legacy-endpoints = "true"
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Pods see the GKE metadata server, which hands out their own Workload
    # Identity credentials and hides the node's.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }
}
