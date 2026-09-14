################################################################################
# Local Values
################################################################################

locals {
  regions = toset(var.regions)

  # Protection plans keyed by the GuardDuty feature name. Every plan is written
  # to every detector as ENABLED or DISABLED so the applied state is explicit.
  protection_plans = {
    S3_DATA_EVENTS         = var.s3_protection_enabled
    EKS_AUDIT_LOGS         = var.eks_protection_enabled
    EBS_MALWARE_PROTECTION = var.malware_protection_enabled
    RDS_LOGIN_EVENTS       = var.rds_protection_enabled
    LAMBDA_NETWORK_LOGS    = var.lambda_protection_enabled
    RUNTIME_MONITORING     = var.runtime_monitoring_enabled
  }

  runtime_monitoring_additional_configuration = {
    for agent in ["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT"] :
    agent => var.runtime_monitoring_enabled && contains(var.runtime_monitoring_automated_agents, agent)
  }

  # One entry per (region, feature) pair: "<region>/<feature>".
  detector_features = {
    for pair in setproduct(local.regions, keys(local.protection_plans)) :
    "${pair[0]}/${pair[1]}" => {
      region  = pair[0]
      feature = pair[1]
      enabled = local.protection_plans[pair[1]]
    }
  }

  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/guardduty"
  }

  tags = merge(local.default_tags, var.tags)
}
