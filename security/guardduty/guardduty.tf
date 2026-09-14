################################################################################
# Amazon GuardDuty
#
# Enables GuardDuty in every Region listed in var.regions. GuardDuty is a
# Regional service with exactly one detector per account per Region, so the
# module creates one aws_guardduty_detector per Region using the AWS provider's
# per-resource `region` argument (provider >= 6.0) instead of a provider alias
# per Region.
#
# Every protection plan (S3, EKS, Malware, RDS, Lambda, Runtime Monitoring) is
# written explicitly as ENABLED or DISABLED in every Region, so the effective
# configuration is fully declared here rather than inherited from AWS defaults.
#
# Findings are delivered to EventBridge in each Region automatically. Routing
# findings to a central bus, S3 export, or Security Hub is left to the
# composition level.
################################################################################

data "aws_caller_identity" "current" {}

# Regions the account has enabled (opted in). GuardDuty cannot be enabled in a
# Region the account is not opted into, so fail early with a clear message.
data "aws_regions" "enabled" {
  all_regions = false
}

resource "aws_guardduty_detector" "this" {
  for_each = local.regions

  region = each.key

  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  tags = local.tags

  lifecycle {
    precondition {
      condition     = contains(data.aws_regions.enabled.names, each.key)
      error_message = "Region ${each.key} is not enabled for this AWS account. Opt in to the Region (or remove it from regions) before enabling GuardDuty there."
    }
  }
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = local.detector_features

  region = each.value.region

  detector_id = aws_guardduty_detector.this[each.value.region].id
  name        = each.value.feature
  status      = each.value.enabled ? "ENABLED" : "DISABLED"

  dynamic "additional_configuration" {
    for_each = each.value.feature == "RUNTIME_MONITORING" ? local.runtime_monitoring_additional_configuration : {}

    content {
      name   = additional_configuration.key
      status = additional_configuration.value ? "ENABLED" : "DISABLED"
    }
  }
}
