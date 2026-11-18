################################################################################
# Record sets
################################################################################

resource "google_dns_record_set" "this" {
  for_each = local.records

  managed_zone = local.zone_name
  name         = each.value.fqdn
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.routing_policy == null ? each.value.rrdatas : null

  dynamic "routing_policy" {
    for_each = each.value.routing_policy == null ? [] : [each.value.routing_policy]

    content {
      dynamic "wrr" {
        for_each = routing_policy.value.type == "WEIGHTED" ? routing_policy.value.items : []

        content {
          weight  = wrr.value.weight
          rrdatas = wrr.value.rrdatas
        }
      }

      dynamic "geo" {
        for_each = routing_policy.value.type == "GEO" ? routing_policy.value.items : []

        content {
          location = geo.value.key
          rrdatas  = geo.value.rrdatas
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = endswith(each.value.fqdn, local.dns_name)
      error_message = "Record ${each.value.fqdn} is not inside the zone ${local.dns_name}."
    }
  }
}
