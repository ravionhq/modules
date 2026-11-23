# GCP Network Load Balancer module tests — run from module root: tofu test

mock_provider "google" {
  override_resource {
    target = google_compute_address.this
    values = {
      address = "203.0.113.10"
    }
  }
}

variables {
  name       = "game"
  project_id = "acme-prod-123"
  region     = "us-central1"
  network    = "projects/acme-prod-123/global/networks/acme-prod"
  ports      = ["7777"]
  protocol   = "UDP"
  backends   = [{ group = "projects/acme-prod-123/regions/us-central1/instanceGroups/game" }]
  health_check = {
    port = 8080
  }
  target_tags = ["game"]
}

run "external_udp" {
  command = plan

  assert {
    condition     = google_compute_forwarding_rule.this.load_balancing_scheme == "EXTERNAL" && google_compute_forwarding_rule.this.ip_address == "203.0.113.10"
    error_message = "An external forwarding rule should use the reserved address."
  }

  assert {
    condition     = google_compute_region_backend_service.this.load_balancing_scheme == "EXTERNAL" && google_compute_region_backend_service.this.protocol == "UDP"
    error_message = "The backend service should be an external UDP backend service."
  }

  assert {
    condition     = contains(google_compute_firewall.health_checks[0].source_ranges, "209.85.152.0/22") && one(google_compute_firewall.health_checks[0].allow).ports[0] == "8080"
    error_message = "Health check firewall should allow external health check ranges on the TCP health check port."
  }

  assert {
    condition     = one(google_compute_firewall.clients[0].allow).protocol == "udp" && one(google_compute_firewall.clients[0].allow).ports[0] == "7777"
    error_message = "The client firewall should allow UDP on the listener port."
  }
}

run "internal_needs_subnetwork" {
  command = plan

  variables {
    internal_load_balancer_enabled = true
  }

  expect_failures = [google_compute_forwarding_rule.this]
}

run "internal_all_protocols" {
  command = plan

  variables {
    internal_load_balancer_enabled = true
    subnetwork                     = "projects/acme-prod-123/regions/us-central1/subnetworks/acme-prod-us-central1"
    protocol                       = "L3_DEFAULT"
    ports                          = []
    global_access_enabled          = true
    ingress_source_ranges          = ["10.0.0.0/12"]
  }

  assert {
    condition = (
      google_compute_forwarding_rule.this.all_ports == true &&
      google_compute_forwarding_rule.this.allow_global_access == true &&
      google_compute_region_backend_service.this.protocol == "UNSPECIFIED"
    )
    error_message = "L3_DEFAULT should forward all ports with an UNSPECIFIED backend service protocol."
  }

  assert {
    condition     = contains(google_compute_firewall.health_checks[0].source_ranges, "130.211.0.0/22") && one(google_compute_firewall.clients[0].allow).protocol == "all"
    error_message = "Internal health check ranges and an all-protocol client rule are expected."
  }
}

run "l3_default_rejects_ports" {
  command = plan

  variables {
    protocol = "L3_DEFAULT"
  }

  expect_failures = [var.ports]
}

run "failover_rejected_on_external" {
  command = plan

  variables {
    backends = [{ group = "projects/acme-prod-123/regions/us-central1/instanceGroups/game", failover = true }]
  }

  expect_failures = [google_compute_region_backend_service.this]
}
