# GCP DNS module tests — run from module root: tofu test

mock_provider "google" {
  override_resource {
    target = google_dns_managed_zone.this
    values = {
      id           = "projects/acme-prod-123/managedZones/example-com"
      name_servers = ["ns-cloud-a1.googledomains.com.", "ns-cloud-a2.googledomains.com."]
    }
  }

  override_data {
    target = data.google_dns_managed_zone.existing
    values = {
      dns_name   = "existing.example.com."
      visibility = "public"
    }
  }
}

variables {
  project_id = "acme-prod-123"
}

run "public_zone_with_records" {
  command = plan

  variables {
    dns_name              = "Example.com"
    query_logging_enabled = true
    records = [
      { name = "@", type = "TXT", rrdatas = ["\"v=spf1 -all\""] },
      { name = "www.example.com", type = "CNAME", rrdatas = ["example.com."] },
      {
        name = "api.example.com."
        type = "A"
        routing_policy = {
          type = "WEIGHTED"
          items = [
            { key = "blue", weight = 90, rrdatas = ["203.0.113.10"] },
            { key = "green", weight = 10, rrdatas = ["203.0.113.20"] },
          ]
        }
      },
    ]
  }

  assert {
    condition     = google_dns_managed_zone.this[0].name == "example-com" && google_dns_managed_zone.this[0].dns_name == "example.com."
    error_message = "The zone name should be derived from the domain, and the domain normalized."
  }

  assert {
    condition     = one(google_dns_managed_zone.this[0].cloud_logging_config).enable_logging == true && length(google_dns_policy.logging) == 0
    error_message = "A public zone should log through zone logging, not a server policy."
  }

  assert {
    condition     = google_dns_record_set.this["TXT @"].name == "example.com." && google_dns_record_set.this["CNAME www.example.com"].name == "www.example.com."
    error_message = "Record names should be normalized to fully qualified names."
  }

  assert {
    condition     = length(one(google_dns_record_set.this["A api.example.com."].routing_policy).wrr) == 2
    error_message = "The weighted record should have two weighted answers."
  }
}

run "private_zone_logs_through_server_policy" {
  command = plan

  variables {
    dns_name                    = "internal.example.com"
    private_zone_enabled        = true
    private_visibility_networks = ["projects/acme-prod-123/global/networks/acme-prod"]
    query_logging_enabled       = true
    dnssec_enabled              = true
  }

  assert {
    condition     = google_dns_managed_zone.this[0].visibility == "private" && length(google_dns_managed_zone.this[0].dnssec_config) == 0
    error_message = "A private zone should have no DNSSEC config even when DNSSEC is requested."
  }

  assert {
    condition     = google_dns_policy.logging[0].name == "internal-example-com-logging" && google_dns_policy.logging[0].enable_logging
    error_message = "A private zone with query logging should create a logging server policy."
  }
}

run "private_zone_requires_networks" {
  command = plan

  variables {
    dns_name             = "internal.example.com"
    private_zone_enabled = true
  }

  expect_failures = [google_dns_managed_zone.this]
}

run "fully_qualified_record_outside_zone_fails" {
  command = plan

  variables {
    zone_creation_enabled = false
    zone_name             = "existing-zone"
    records = [
      { name = "app.other.com.", type = "A", rrdatas = ["203.0.113.10"] },
    ]
  }

  expect_failures = [google_dns_record_set.this]
}

run "existing_zone_valid_records" {
  command = plan

  variables {
    zone_creation_enabled = false
    zone_name             = "existing-zone"
    records = [
      { name = "@", type = "MX", rrdatas = ["10 mx.example.net."] },
      { name = "app", type = "A", rrdatas = ["203.0.113.10"] },
      { name = "api.existing.example.com", type = "A", rrdatas = ["203.0.113.11"] },
    ]
  }

  assert {
    condition     = length(google_dns_managed_zone.this) == 0 && google_dns_record_set.this["MX @"].name == "existing.example.com."
    error_message = "Records should go into the existing zone's apex."
  }

  assert {
    condition     = google_dns_record_set.this["A app"].name == "app.existing.example.com." && google_dns_record_set.this["A api.existing.example.com"].name == "api.existing.example.com."
    error_message = "Relative names should get the zone domain appended, and names already in the zone should not."
  }
}

run "routing_policy_and_rrdatas_conflict" {
  command = plan

  variables {
    dns_name = "example.com"
    records = [
      {
        name    = "api.example.com"
        type    = "A"
        rrdatas = ["203.0.113.10"]
        routing_policy = {
          type  = "GEO"
          items = [{ key = "us-central1", rrdatas = ["203.0.113.10"] }]
        }
      },
    ]
  }

  expect_failures = [var.records]
}

run "numeric_domain_gets_letter_prefix" {
  command = plan

  variables {
    dns_name = "123.example.com"
  }

  assert {
    condition     = google_dns_managed_zone.this[0].name == "z-123-example-com"
    error_message = "A zone name generated from a domain starting with a digit should start with a letter."
  }
}

run "weight_defaults_to_one" {
  command = plan

  variables {
    dns_name = "example.com"
    records = [
      {
        name = "api"
        type = "A"
        routing_policy = {
          type  = "WEIGHTED"
          items = [{ key = "blue", weight = null, rrdatas = ["203.0.113.10"] }]
        }
      },
    ]
  }

  assert {
    condition     = one(google_dns_record_set.this["A api"].routing_policy).wrr[0].weight == 1
    error_message = "A weighted answer without a weight should default to 1."
  }
}

run "equivalent_record_names_are_duplicates" {
  command = plan

  variables {
    dns_name = "example.com"
    records = [
      { name = "www", type = "A", rrdatas = ["203.0.113.10"] },
      { name = "www.example.com.", type = "A", rrdatas = ["203.0.113.11"] },
    ]
  }

  expect_failures = [google_dns_record_set.this]
}
