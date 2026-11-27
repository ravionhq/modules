mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = { email = "test-cluster-nodes@test-project.iam.gserviceaccount.com" }
  }
}

variables {
  name       = "test-cluster"
  project_id = "test-project"
  region     = "us-central1"
}

# Ravion passes its standard tags (ProjectGivenId, ...), which GCP rejects as
# label keys; they must reach the cluster normalized instead of failing apply.
run "labels_are_normalized_for_gcp" {
  command = plan

  variables {
    labels = {
      ProjectGivenId = "My.Project"
      Owner          = "Ravion"
    }
  }

  assert {
    condition = google_container_cluster.this.resource_labels == tomap({
      managed_by     = "terraform"
      module         = "compute-gke"
      projectgivenid = "my_project"
      owner          = "ravion"
    })
    error_message = "Labels must be lowercased with invalid characters replaced."
  }
}

# Owner (a Ravion tag) and owner (a user tag) normalize to the same label key;
# they must not fail the plan with a duplicate key, and keys must start with a
# letter.
run "colliding_and_digit_label_keys_are_resolved" {
  command = plan

  variables {
    labels = {
      Owner     = "Ravion"
      owner     = "platform"
      "123team" = "infra"
    }
  }

  assert {
    condition     = google_container_cluster.this.resource_labels["owner"] == "platform" && google_container_cluster.this.resource_labels["x_123team"] == "infra"
    error_message = "Colliding keys must resolve to one label and digit-leading keys must get a letter prefix."
  }
}

# Clusters sharing a long name prefix, or one name in two regions, must not
# collide on the project-unique node service account ID.
run "node_service_account_id_is_unique_per_cluster" {
  command = plan

  variables {
    name = "acme-production-platform-east"
  }

  assert {
    condition     = can(regex("^acme-production-p-[0-9a-f]{6}-nodes$", google_service_account.nodes[0].account_id))
    error_message = "The node service account ID must keep a prefix plus a hash of the name and region, within 30 characters."
  }

  assert {
    condition     = google_service_account.nodes[0].account_id != "${substr("acme-production-platform-west", 0, 17)}-${substr(sha256("acme-production-platform-west/us-central1"), 0, 6)}-nodes"
    error_message = "A sibling cluster with the same prefix must get a different node service account ID."
  }
}

run "private_nodes_with_workload_identity_and_dedicated_node_account" {
  command = plan

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes && google_container_cluster.this.private_cluster_config[0].enable_private_endpoint
    error_message = "Nodes and the IP endpoint must be private by default."
  }

  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "test-project.svc.id.goog"
    error_message = "Workload Identity must be enabled."
  }

  assert {
    condition     = google_container_node_pool.this["system"].node_config[0].service_account == "test-cluster-nodes@test-project.iam.gserviceaccount.com"
    error_message = "Nodes must run as the dedicated node service account, not the Compute Engine default account."
  }

  assert {
    condition     = google_container_node_pool.this["system"].node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "Pods must not see the node's credentials."
  }
}

run "spot_pool_uses_any_zone_and_system_pool_keeps_its_label" {
  command = plan

  variables {
    node_pools = {
      batch = {
        capacity_type = "SPOT"
        min_nodes     = 0
        max_nodes     = 10
      }
    }
  }

  assert {
    condition     = google_container_node_pool.this["batch"].node_config[0].spot && google_container_node_pool.this["batch"].autoscaling[0].location_policy == "ANY"
    error_message = "Spot pools must be Spot and free to use any zone with capacity."
  }

  assert {
    condition     = google_container_node_pool.this["batch"].initial_node_count == 0
    error_message = "A pool with no minimum must start empty."
  }

  assert {
    condition     = google_container_node_pool.this["system"].node_config[0].labels == tomap({ role = "system" }) && !google_container_node_pool.this["system"].node_config[0].spot
    error_message = "The system pool must stay On-demand and labelled role=system."
  }
}

run "existing_node_account_requires_an_email" {
  command = plan

  variables {
    node_service_account_creation_enabled = false
  }

  expect_failures = [var.node_service_account_email]
}
