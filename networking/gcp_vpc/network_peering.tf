################################################################################
# VPC Network Peering
################################################################################

resource "google_compute_network_peering" "this" {
  for_each = var.network_peerings

  name                 = "${var.name}-${each.key}"
  network              = google_compute_network.this.self_link
  peer_network         = each.value.peer_network
  export_custom_routes = each.value.export_custom_routes
  import_custom_routes = each.value.import_custom_routes

  # Only one peering operation can run on a network at a time, and the
  # Private Service Access connection is a peering too.
  depends_on = [google_service_networking_connection.private_service_access]
}
