# GCP VPC module tests — run from module root: tofu test

mock_provider "google" {}

variables {
  name       = "acme-prod"
  project_id = "acme-prod-123"
  region     = "us-central1"
}

run "default_address_plan" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.this["us-central1"].ip_cidr_range == "10.1.0.0/20"
    error_message = "The primary subnetwork should use 10.1.0.0/20."
  }

  assert {
    condition = (
      local.region_ranges["us-central1"].pods == "10.0.0.0/16" &&
      local.region_ranges["us-central1"].services == "10.1.16.0/20" &&
      local.region_ranges["us-central1"].proxy_only == "10.1.32.0/23"
    )
    error_message = "The primary region's secondary and proxy-only ranges are wrong."
  }

  assert {
    condition     = google_compute_global_address.private_service_access[0].address == "10.14.0.0" && google_compute_global_address.private_service_access[0].prefix_length == 16
    error_message = "Private Service Access should reserve 10.14.0.0/16."
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 1 && length(google_compute_address.nat) == 1
    error_message = "One Cloud NAT with one static address should be created by default."
  }

  assert {
    condition     = google_compute_router_nat.this["us-central1"].nat_ip_allocate_option == "MANUAL_ONLY"
    error_message = "Cloud NAT should use the reserved static address."
  }

  assert {
    condition     = length(google_compute_subnetwork.proxy_only) == 0 && length(google_compute_firewall.internal_ingress) == 0
    error_message = "Proxy-only subnetworks and the allow-internal rule should be off by default."
  }
}

run "additional_regions_get_their_own_blocks" {
  command = plan

  variables {
    additional_regions                     = ["europe-west1"]
    proxy_only_subnetwork_creation_enabled = true
    firewall_internal_ingress_enabled      = true
  }

  assert {
    condition     = google_compute_subnetwork.this["europe-west1"].ip_cidr_range == "10.3.0.0/20"
    error_message = "The second region's subnetwork should use 10.3.0.0/20."
  }

  assert {
    condition     = google_compute_subnetwork.proxy_only["europe-west1"].ip_cidr_range == "10.3.32.0/23"
    error_message = "The second region's proxy-only subnetwork should use 10.3.32.0/23."
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 2 && length(google_compute_address.nat) == 2
    error_message = "Each region should get its own Cloud NAT and address."
  }

  assert {
    condition     = contains(google_compute_firewall.internal_ingress[0].source_ranges, "10.2.0.0/16") && contains(google_compute_firewall.internal_ingress[0].source_ranges, "10.3.32.0/23")
    error_message = "The allow-internal rule should include pods and proxy-only ranges of every region."
  }
}

run "supplied_and_automatic_nat_addresses" {
  command = plan

  variables {
    additional_regions  = ["europe-west1"]
    nat_static_ip_count = 0
    nat_ip_self_links = {
      "europe-west1" = ["projects/acme-prod-123/regions/europe-west1/addresses/partner-ip"]
    }
  }

  assert {
    condition     = length(google_compute_address.nat) == 0
    error_message = "No addresses should be reserved when the count is 0 and the other region supplies its own."
  }

  assert {
    condition = (
      google_compute_router_nat.this["us-central1"].nat_ip_allocate_option == "AUTO_ONLY" &&
      google_compute_router_nat.this["europe-west1"].nat_ip_allocate_option == "MANUAL_ONLY"
    )
    error_message = "The primary region should allocate automatically and europe-west1 should use the supplied address."
  }
}

run "everything_optional_disabled" {
  command = plan

  variables {
    nat_enabled                         = false
    private_service_access_enabled      = false
    subnetwork_secondary_ranges_enabled = false
    flow_logs_enabled                   = false
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 0 && length(google_service_networking_connection.private_service_access) == 0
    error_message = "Cloud NAT and Private Service Access should not be created."
  }

  assert {
    condition     = length(google_compute_subnetwork.this["us-central1"].secondary_ip_range) == 0 && length(google_compute_subnetwork.this["us-central1"].log_config) == 0
    error_message = "The subnetwork should have no secondary ranges or flow logs."
  }

  assert {
    condition     = output.private_service_access_range_name == null && output.pods_secondary_range_name == null
    error_message = "Disabled features should output null."
  }
}

run "firewall_rule_rejects_egress_without_destination" {
  command = plan

  variables {
    firewall_rules = {
      bad = {
        direction = "EGRESS"
        ports     = ["443"]
      }
    }
  }

  expect_failures = [var.firewall_rules]
}

run "firewall_rule_iap_ssh" {
  command = plan

  variables {
    firewall_rules = {
      iap-ssh = {
        source_ranges = ["35.235.240.0/20"]
        ports         = ["22"]
        target_tags   = ["ssh"]
      }
    }
  }

  assert {
    condition     = google_compute_firewall.this["iap-ssh"].name == "acme-prod-iap-ssh" && one(google_compute_firewall.this["iap-ssh"].allow).ports[0] == "22"
    error_message = "The IAP SSH rule should be named after the network and allow tcp:22."
  }
}
