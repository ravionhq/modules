################################################################################
# Custom rules
#
# A web ACL takes either rule blocks or raw rule JSON, not both. Arbitrary
# rules therefore go into their own rule group as JSON, which the web ACL
# evaluates at the custom_rules priority next to the module's rules.
################################################################################

resource "aws_wafv2_rule_group" "custom" {
  count = var.custom_rules_json == null ? 0 : 1

  region = local.region

  # Capacity can only change by replacing the group, and AWS refuses to delete
  # a group the web ACL still references. A generated name lets the new group
  # exist beside the old one: it is created, the web ACL switches to it, and
  # then the old group is deleted.
  name_prefix = "${substr(var.name, 0, 100)}-custom-"
  scope       = local.scope
  capacity    = var.custom_rules_capacity
  rules_json  = var.custom_rules_json
  tags        = local.tags

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.metric_prefix}-custom"
    sampled_requests_enabled   = true
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.custom_rules_capacity != null
      error_message = "custom_rules_json needs custom_rules_capacity."
    }
  }
}
