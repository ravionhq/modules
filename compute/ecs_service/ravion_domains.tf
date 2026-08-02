################################################################################
# Ravion-managed service domains
################################################################################
# Wired when cluster_parent_fqdn is set (piped from ecs_cluster). The `domains`
# list is the single source of truth — each entry is classified by whether the
# cluster wildcard cert covers it:
#
#   - wildcard-covered (<leaf>.<apex>, exactly one label under the cluster apex):
#     nests under the cluster wildcard cert via SNI. No per-service cert, and no
#     per-domain DNS record — the cluster's `*.<apex>` ALIAS already routes it.
#   - custom (anything else — external FQDNs, or names deeper than one label
#     under the apex the wildcard can't cover): covered by ONE per-service
#     instance ACM cert (<=10 SANs) attached to the cluster listener, plus a
#     routing record the customer adds.
#
# When `domains` is empty the service still gets an auto-FQDN
# `<given-id>.<apex>` (a wildcard-covered entry), so a service with no custom
# domains is reachable out of the box.

locals {
  ravion_managed = var.cluster_parent_fqdn != null && var.cluster_parent_fqdn != ""
  apex           = local.ravion_managed ? lower(var.cluster_parent_fqdn) : ""

  # Auto-FQDN used when the domains list is empty (matches the frontend default).
  auto_fqdn = local.ravion_managed ? "${coalesce(var.module_instance_given_id, var.name)}.${local.apex}" : ""

  # The effective list: the user's domains (or the auto-FQDN when empty),
  # normalized — lowercased, trailing dot + surrounding whitespace stripped,
  # empties dropped. Keeps classification consistent with DNS case-insensitivity
  # and the backend's lowercase sanitizeLabel.
  effective_domains = local.ravion_managed ? [
    for d in(length(var.domains) > 0 ? var.domains : [local.auto_fqdn]) :
    lower(trimsuffix(trimspace(d), ".")) if trimspace(d) != ""
  ] : []

  # Per-entry classification. wildcard-covered = "<leaf>.<apex>" with a non-empty
  # single label below the apex (the only shape the `*.<apex>` cert + ALIAS
  # cover). The non-empty-leaf guard keeps a malformed ".<apex>" out of the
  # wildcard bucket (an empty leaf would produce an invalid ALB host header).
  wildcard_covered = [
    for d in local.effective_domains : d
    if endswith(d, ".${local.apex}") && length(trimsuffix(d, ".${local.apex}")) > 0 && !strcontains(trimsuffix(d, ".${local.apex}"), ".")
  ]
  custom_domains = [
    for d in local.effective_domains : d
    if !(endswith(d, ".${local.apex}") && length(trimsuffix(d, ".${local.apex}")) > 0 && !strcontains(trimsuffix(d, ".${local.apex}"), "."))
  ]

  # Domains under the cluster apex that are NOT a single-label `<leaf>.<apex>`:
  # the bare apex itself, or a name more than one label deep. The `*.<apex>`
  # wildcard cert covers exactly one label, and the customer cannot add records
  # to the Ravion-managed zone, so these can never be satisfied — they fall into
  # custom_domains today and would silently emit a per-service cert + an
  # unwritable routing record. Fail the plan instead (the server-side
  # RejectCustomDomainUnderApex is the same backstop for direct-API callers).
  invalid_apex_domains = [
    for d in local.custom_domains : d
    if d == local.apex || endswith(d, ".${local.apex}")
  ]
  invalid_apex_domains_msg = join(", ", local.invalid_apex_domains)

  # All of this service's hostnames route to its target group. AWS ALB allows at
  # most 5 values in a single rule condition, so the host headers are split into
  # chunks of <=5 — one aws_lb_listener_rule per chunk (see below), each with its
  # own derived priority. (chunklist([], 5) == [], handled by the rule's guard.)
  ravion_host_headers       = local.effective_domains
  ravion_host_header_chunks = chunklist(local.ravion_host_headers, 5)

  # Base listener-rule priority. When ravion_listener_rule_priority is 0 (the
  # default) it is derived from sha256(name) using 12 hex chars (~48 bits) so the
  # collision probability stays low across many services sharing the cluster
  # listener; mod 48000 (instead of 49000) leaves headroom below the ALB max of
  # 50000 for the per-chunk offset (priority = base + chunk index). On a residual
  # collision ("priority already in use") set ravion_listener_rule_priority
  # explicitly to a free value.
  ravion_priority = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : ((parseint(substr(sha256(var.name), 0, 12), 16) % 48000) + 1000)

  ravion_target_group_arn = length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
}

# Wildcard-covered domains (incl. the auto-FQDN): nest under the cluster
# wildcard. No per-service cert; the cluster `*.<apex>` ALIAS routes them.
# Parent-apex authorization (may this service nest under that apex?) runs
# automatically in the provider's ModifyPlan; the control plane enforces the
# same rule at apply against a signed token claim (Dns:PARENT_APEX_UNAUTHORIZED).
resource "ravion_domain" "wildcard" {
  for_each = toset(local.wildcard_covered)

  name               = trimsuffix(each.value, ".${local.apex}")
  module_instance_id = var.module_instance_id
  parent_domain_name = local.apex

  lifecycle {
    precondition {
      condition     = var.module_instance_id != null && var.module_instance_id != ""
      error_message = "module_instance_id (minst_*) is required for Ravion-managed domains. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}

# Per-service certificate covering the custom (non-wildcard) domains (<=10 SANs),
# attached to the cluster listener via Ravion.
resource "ravion_aws_acm_certificate" "svc" {
  count = length(local.custom_domains) > 0 ? 1 : 0

  domains            = local.custom_domains
  module_instance_id = var.module_instance_id
  aws_account_id     = var.ravion_aws_account_id
  aws_region         = coalesce(var.ravion_aws_region, local.region)
  target_arn         = var.cluster_https_listener_arn

  lifecycle {
    precondition {
      condition     = length(local.invalid_apex_domains) == 0
      error_message = "Domains under the cluster apex must be a single label that rides the cluster wildcard, like checkout.${local.apex}. These entries are the bare apex or more than one label deep, so the wildcard certificate does not cover them and their routing record would have to live in the Ravion-managed zone (which you cannot edit): ${local.invalid_apex_domains_msg}. Use a single-label name under the apex, or a domain in a DNS zone you control."
    }
    precondition {
      condition     = length(local.custom_domains) == 0 || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id is required when the domains list includes a custom (non-wildcard) domain."
    }
    precondition {
      condition     = length(local.custom_domains) == 0 || (var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != "")
      error_message = "cluster_https_listener_arn is required when the domains list includes a custom (non-wildcard) domain."
    }
    precondition {
      condition     = length(local.custom_domains) <= 10
      error_message = "A service may declare at most 10 custom (non-wildcard) domains (one cert per service)."
    }
    precondition {
      condition     = length(local.custom_domains) == 0 || (var.module_instance_id != null && var.module_instance_id != "")
      error_message = "module_instance_id (minst_*) is required when the domains list includes a custom (non-wildcard) domain. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}

# Routing records the customer must add for each custom domain (one per FQDN).
resource "ravion_domain" "custom" {
  for_each = toset(local.custom_domains)

  name               = each.value
  module_instance_id = var.module_instance_id
  target_dns_name    = var.cluster_alb_dns_name
  target_zone_id     = var.cluster_alb_zone_id

  lifecycle {
    # Mirror of the sibling cert's cluster_https_listener_arn guard: without a
    # routing target the API happily creates a domain row that never resolves —
    # a silent production failure instead of a plan-time message.
    precondition {
      condition     = var.cluster_alb_dns_name != null && var.cluster_alb_dns_name != "" && var.cluster_alb_zone_id != null && var.cluster_alb_zone_id != ""
      error_message = "cluster_alb_dns_name and cluster_alb_zone_id are required when the domains list includes a custom (non-wildcard) domain — they are the routing target its CNAME points at."
    }
    precondition {
      condition     = var.module_instance_id != null && var.module_instance_id != ""
      error_message = "module_instance_id (minst_*) is required for Ravion-managed domains. Inside a stack run the runner injects TF_VAR_module_instance_id; set it explicitly for external runs."
    }
  }
}

# One listener rule per chunk of <=5 host headers (AWS ALB's per-condition value
# quota), together routing all of this service's hostnames to its target group.
# Each chunk gets its own priority (base + chunk index). Chunk "0" doubles as
# the production listener rule handed to ECS advanced_configuration, whose
# deployment controller rewrites its forward action during native traffic-shift
# deploys (hence ignore_changes on action); an ecs_service precondition caps
# traffic-shift services at one chunk so no rule is left behind on the old
# revision.
resource "aws_lb_listener_rule" "ravion" {
  for_each = local.ravion_managed && var.cluster_https_listener_arn != null && length(local.ravion_host_headers) > 0 ? {
    for idx, chunk in local.ravion_host_header_chunks : idx => chunk
  } : {}

  listener_arn = var.cluster_https_listener_arn
  priority     = local.ravion_priority + tonumber(each.key)

  condition {
    host_header {
      values = each.value
    }
  }

  # Same group-stickiness requirement as the BYO production rule: ECS rewrites
  # chunk "0" to a weighted two-target-group forward during native traffic-shift
  # deploys, and ELBv2 rejects that rewrite when a sticky target group is
  # referenced without group-level stickiness on the action ("You must enable
  # group stickiness on a rule if you enabled target stickiness on one of its
  # target groups").
  action {
    type             = "forward"
    target_group_arn = local.alb_group_stickiness_enabled ? null : local.ravion_target_group_arn

    dynamic "forward" {
      for_each = local.alb_group_stickiness_enabled ? [1] : []
      content {
        target_group {
          arn = local.ravion_target_group_arn
        }
        stickiness {
          enabled  = true
          duration = local.alb_group_stickiness_duration
        }
      }
    }
  }

  lifecycle {
    # A Ravion-managed service forwards its hostnames to its own target group, so
    # it must have a load balancer attachment. Without one ravion_target_group_arn
    # is null, which would otherwise surface as a cryptic provider-side
    # "target_group_arn must not be empty" at apply.
    precondition {
      condition     = !local.ravion_managed || local.enable_load_balancer
      error_message = "A Ravion-managed service (cluster_parent_fqdn set) requires an enabled load_balancer_attachment so its hostnames have a target group to forward to."
    }
    ignore_changes = [action]
  }
}
