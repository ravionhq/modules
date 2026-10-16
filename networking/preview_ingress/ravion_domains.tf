################################################################################
# Custom Domains
################################################################################

# A custom domain is a wildcard, *.<domain>, in a DNS zone the customer
# controls. A preview served under it takes one hostname below the wildcard,
# as previews do under the managed wildcard domain. The managed wildcard
# certificate (certificate.tf) stays the TLS listener's default certificate;
# the custom domains share one more certificate, which the load balancer
# picks by the hostname a client asks for.

locals {
  # Lowercased, without surrounding whitespace or a trailing dot, each listed
  # once in the order given. Blank entries are dropped.
  custom_domains = distinct([
    for domain in var.domains :
    lower(trimsuffix(trimspace(domain), ".")) if trimsuffix(trimspace(domain), ".") != ""
  ])

  # The managed wildcard domain is <name>.<ravion-apex>: without its first
  # label it is Ravion's own apex.
  managed_domain_labels = split(".", lower(ravion_aws_acm_certificate.this.domain_name))
  ravion_apex           = join(".", slice(local.managed_domain_labels, 1, length(local.managed_domain_labels)))

  # Custom domains under Ravion's apex. Their certificate and routing records
  # would have to live in Ravion's DNS zone, which a customer cannot edit, so
  # they could never be validated or resolved. The Ravion API refuses them as
  # well.
  invalid_apex_domains = [
    for domain in local.custom_domains : domain
    if local.ravion_apex != "" && (trimprefix(domain, "*.") == local.ravion_apex || endswith(domain, ".${local.ravion_apex}"))
  ]
}

# One certificate for every custom domain (at most 10 names), attached to the
# TLS listener by Ravion. It is issued once the customer has added the
# validation records; the apply does not wait for that.
resource "ravion_aws_acm_certificate" "custom" {
  count = length(local.custom_domains) > 0 ? 1 : 0

  domains            = local.custom_domains
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = local.region
  target_arn         = aws_lb_listener.tls.arn

  lifecycle {
    precondition {
      condition     = length(local.invalid_apex_domains) == 0
      error_message = "Custom domains must be in a DNS zone you control. These entries are under Ravion's managed apex ${local.ravion_apex}, where you cannot add the records a custom domain needs: ${join(", ", local.invalid_apex_domains)}. Previews are already served under the managed wildcard domain ${ravion_aws_acm_certificate.this.domain_name}."
    }
  }
}

# The routing record the customer adds for each custom domain: the wildcard
# points at the load balancer.
resource "ravion_domain" "custom" {
  for_each = toset(local.custom_domains)

  name               = each.value
  module_instance_id = var.module_instance_id
  target_dns_name    = aws_lb.this.dns_name
  target_zone_id     = aws_lb.this.zone_id
}
