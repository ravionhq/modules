################################################################################
# GKE cluster
#
# A regional, VPC-native Standard cluster with private nodes. It starts with no
# default node pool (initial_node_count and node_config are omitted); every
# pool, the system pool included, is a google_container_node_pool below so it
# can be replaced without touching the cluster.
################################################################################

resource "google_container_cluster" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region

  node_locations      = var.node_locations
  deletion_protection = var.deletion_protection_enabled
  resource_labels     = local.labels

  # Every pool is a separate resource, so the inline pool list never needs
  # refreshing.
  skip_node_pool_refresh = true

  network           = var.network
  subnetwork        = var.subnetwork
  networking_mode   = "VPC_NATIVE"
  datapath_provider = var.dataplane_v2_enabled ? "ADVANCED_DATAPATH" : "LEGACY_DATAPATH"

  ip_allocation_policy {
    stack_type                    = "IPV4"
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
    cluster_ipv4_cidr_block       = var.pods_ipv4_cidr_block
    services_ipv4_cidr_block      = var.services_ipv4_cidr_block
  }

  # Nodes never get external IPs. Without a master_ipv4_cidr_block GKE uses
  # Private Service Connect for the control plane, so no peering range is
  # reserved.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = !var.ip_endpoint_public_access_enabled
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = var.dns_endpoint_enabled
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidr_blocks
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  min_master_version = var.kubernetes_version

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = var.gateway_api_enabled ? "CHANNEL_STANDARD" : "CHANNEL_DISABLED"
  }

  database_encryption {
    state    = var.secrets_kms_key_name == null ? "DECRYPTED" : "ENCRYPTED"
    key_name = var.secrets_kms_key_name
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = var.managed_prometheus_enabled
    }
  }

  # Node auto-provisioning is GKE's equivalent of Karpenter: pending pods that
  # fit no pool get a new pool shaped for them, within the limits below.
  cluster_autoscaling {
    enabled             = var.node_auto_provisioning_enabled
    autoscaling_profile = var.autoscaling_profile

    dynamic "resource_limits" {
      for_each = var.node_auto_provisioning_enabled ? {
        cpu    = var.node_auto_provisioning_cpu_limit
        memory = var.node_auto_provisioning_memory_limit_gb
      } : {}
      content {
        resource_type = resource_limits.key
        maximum       = resource_limits.value
      }
    }

    dynamic "auto_provisioning_defaults" {
      for_each = var.node_auto_provisioning_enabled ? [true] : []
      content {
        service_account = local.node_service_account_email
        oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
        disk_type       = "pd-balanced"

        management {
          auto_repair  = true
          auto_upgrade = true
        }

        shielded_instance_config {
          enable_secure_boot          = true
          enable_integrity_monitoring = true
        }
      }
    }
  }

  depends_on = [
    google_project_service.container,
    google_project_iam_member.nodes,
  ]
}
