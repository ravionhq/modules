################################################################################
# Ravion-managed custom domains
################################################################################
# Each distribution with managed_domains gets one ACM certificate in us-east-1
# (<=10 SANs) plus a routing record per domain for the customer to add. Once DNS
# validates, Ravion attaches the certificate and sets the aliases to its
# domains, which is why aws_cloudfront_distribution.this ignores both. Until
# then the distribution keeps serving what it served before.

locals {
  managed_distributions = {
    for k, v in var.distributions : k => v if length(v.managed_domains) > 0
  }

  # Lowercased and de-duplicated, so the first entry stays the primary domain.
  managed_domain_names = {
    for k, v in local.managed_distributions : k => distinct([
      for d in v.managed_domains : lower(trimsuffix(trimspace(d), "."))
    ])
  }

  managed_domain_records = merge([
    for k, domains in local.managed_domain_names : {
      for d in domains : "${k}/${d}" => {
        distribution_key = k
        domain           = d
      }
    }
  ]...)
}

resource "ravion_aws_acm_certificate" "this" {
  for_each = local.managed_distributions

  domains            = local.managed_domain_names[each.key]
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = "us-east-1"
  target_arn         = aws_cloudfront_distribution.this[each.key].arn

  lifecycle {
    precondition {
      condition     = var.ravion_aws_account_id != null && var.ravion_aws_account_id != ""
      error_message = "ravion_aws_account_id is required when a distribution sets managed_domains."
    }
    precondition {
      condition     = var.module_instance_id != null && var.module_instance_id != ""
      error_message = "module_instance_id (minst_*) is required when a distribution sets managed_domains. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}

# Routing records the customer must add for each managed domain.
resource "ravion_domain" "this" {
  for_each = local.managed_domain_records

  name               = each.value.domain
  module_instance_id = var.module_instance_id
  target_dns_name    = aws_cloudfront_distribution.this[each.value.distribution_key].domain_name
  target_zone_id     = aws_cloudfront_distribution.this[each.value.distribution_key].hosted_zone_id

  lifecycle {
    precondition {
      condition     = var.module_instance_id != null && var.module_instance_id != ""
      error_message = "module_instance_id (minst_*) is required when a distribution sets managed_domains. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}
