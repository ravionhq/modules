################################################################################
# Wildcard Certificate and Domain
################################################################################

# Ravion issues one wildcard certificate, *.<name>.<ravion-apex> on its managed
# apex, and publishes the *.<apex> record that points at the load balancer.
# The name leaf defaults to the module instance given id, as a cluster's does.
# Every preview is a hostname under that wildcard. Plan-time guards (an apex
# another module instance already holds, hostnames still allocated on
# teardown) run inside the provider.
resource "ravion_aws_acm_certificate" "this" {
  wildcard           = true
  name               = coalesce(var.ravion_domain_name, var.module_instance_given_id, var.name)
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = local.region

  target_dns_name = aws_lb.this.dns_name
  target_zone_id  = aws_lb.this.zone_id

  lifecycle {
    # A replaced certificate must be issued and swapped onto the TLS listener
    # before the old one is deleted: ACM refuses to delete a certificate a
    # listener still serves.
    create_before_destroy = true
  }
}
