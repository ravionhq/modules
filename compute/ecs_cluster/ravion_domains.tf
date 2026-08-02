################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains = true, Ravion issues ONE wildcard cert
# `*.<name>-<hash>.<ravion-apex>` (+ apex). That cert becomes the default cert
# on the selected cluster ALB's existing HTTPS listener. The cert also publishes
# a `*.<apex>` ALIAS to that ALB so service auto-FQDNs (<svc>.<apex>) resolve.
# When the flag is off, this resource is absent and the listener keeps using the
# customer-supplied certificate ARNs.

locals {
  enable_ravion_domain = var.use_ravion_managed_domains
  ravion_alb_count     = (var.public_alb_enabled ? 1 : 0) + (var.private_alb_enabled ? 1 : 0)
}

# Plan-time guards (wildcard-apex collision against another cluster, and
# dependents on teardown) run automatically inside the provider's ModifyPlan —
# no data source + precondition wiring needed. The allocator enforces the same
# rules server-side as an apply-time backstop.
resource "ravion_aws_acm_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  wildcard           = true
  name               = coalesce(var.ravion_cluster_name, var.module_instance_given_id, var.name)
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = coalesce(var.ravion_aws_region, local.region)

  # Ravion publishes a *.<apex> ALIAS to this ALB so service auto-FQDNs
  # (<svc>.<apex>) resolve under the cluster wildcard. Managed mode intentionally
  # supports exactly one ALB because a wildcard DNS record can target only one
  # load balancer.
  target_dns_name = var.public_alb_enabled ? module.public_alb[0].alb_dns_name : try(module.private_alb[0].alb_dns_name, null)
  target_zone_id  = var.public_alb_enabled ? module.public_alb[0].alb_zone_id : try(module.private_alb[0].alb_zone_id, null)

  lifecycle {
    # Rotating the cluster wildcard cert (any RequiresReplace change, e.g. a
    # renamed apex) must issue the new cert and swap it onto the HTTPS
    # listener(s) BEFORE the old one is torn down. Without this, terraform
    # destroys the old cert first while it is still the listener's default —
    # ACM returns ResourceInUse and the rotation deadlocks. create_before_destroy
    # makes it new -> listener in-place swap -> delete old (now detached).
    create_before_destroy = true

    # A wildcard DNS record can target only one ALB. Supporting simultaneous
    # public/private managed domains requires distinct apexes and certificates.
    precondition {
      condition     = !var.use_ravion_managed_domains || local.ravion_alb_count == 1
      error_message = "use_ravion_managed_domains requires exactly one ALB. Enable either the public ALB or the private ALB, not both. Supporting both requires separate managed apexes and certificates."
    }
    # HTTPS is not optional for the selected managed ALB: its existing listener
    # serves the wildcard certificate as the default certificate.
    precondition {
      condition = (
        !var.use_ravion_managed_domains
        || (var.public_alb_enabled ? var.public_alb_https_enabled : var.private_alb_https_enabled)
      )
      error_message = "use_ravion_managed_domains requires HTTPS on the selected ALB. Enable public_alb_https_enabled or private_alb_https_enabled to serve the wildcard certificate."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.module_instance_id != null && var.module_instance_id != "")
      error_message = "module_instance_id (minst_*) is required when use_ravion_managed_domains = true. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}
