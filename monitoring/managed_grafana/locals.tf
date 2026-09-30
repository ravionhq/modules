################################################################################
# Local Values
################################################################################

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "monitoring/managed_grafana"
  }

  tags = merge(local.default_tags, var.tags)

  identity_center        = var.authentication == "iam_identity_center"
  identity_center_region = coalesce(var.identity_center_region, local.region)

  # A form leaves an unused field blank rather than null.
  prometheus_query_url     = try(trimspace(var.prometheus_query_url), "") == "" ? null : trimsuffix(trimspace(var.prometheus_query_url), "/")
  prometheus_workspace_arn = try(trimspace(var.prometheus_workspace_arn), "") == "" ? null : trimspace(var.prometheus_workspace_arn)
  prometheus_enabled       = local.prometheus_query_url != null && local.prometheus_workspace_arn != null
  prometheus_region        = local.prometheus_enabled ? regex("^https://aps-workspaces\\.([a-z0-9-]+)\\.amazonaws\\.com/", local.prometheus_query_url)[0] : null
  data_source_region       = try(trimspace(var.data_source_region), "") == "" ? local.region : trimspace(var.data_source_region)

  roles = {
    ADMIN  = { users = var.admin_user_names, groups = var.admin_group_names }
    EDITOR = { users = var.editor_user_names, groups = var.editor_group_names }
    VIEWER = { users = var.viewer_user_names, groups = var.viewer_group_names }
  }

  user_names  = distinct(flatten([for role in values(local.roles) : role.users]))
  group_names = distinct(flatten([for role in values(local.roles) : role.groups]))

  user_ids = {
    for user in try(data.aws_identitystore_users.this[0].users, []) : user.user_name => user.user_id
  }
  group_ids = {
    for group in try(data.aws_identitystore_groups.this[0].groups, []) : group.display_name => group.group_id
  }

  missing_user_names  = [for name in local.user_names : name if !contains(keys(local.user_ids), name)]
  missing_group_names = [for name in local.group_names : name if !contains(keys(local.group_ids), name)]

  role_associations = {
    for role, members in local.roles : role => {
      user_ids  = [for name in members.users : local.user_ids[name] if contains(keys(local.user_ids), name)]
      group_ids = [for name in members.groups : local.group_ids[name] if contains(keys(local.group_ids), name)]
    }
    if local.identity_center && length(members.users) + length(members.groups) > 0
  }

  cloudwatch_log_groups = [
    for name in var.cloudwatch_default_log_group_names : {
      name = name
      arn  = "arn:${data.aws_partition.current.partition}:logs:${local.data_source_region}:${data.aws_caller_identity.current.account_id}:log-group:${name}"
    }
  ]

  # Grafana data sources the module owns, by stable UID. The UIDs of disabled
  # ones are removed from the workspace.
  data_sources = concat(
    var.xray_enabled ? [{
      uid    = "aws-xray"
      name   = "AWS X-Ray"
      type   = "grafana-x-ray-datasource"
      access = "proxy"
      jsonData = {
        authType      = "ec2_iam_role"
        defaultRegion = local.data_source_region
      }
    }] : [],
    var.cloudwatch_enabled ? [{
      uid    = "aws-cloudwatch"
      name   = "CloudWatch"
      type   = "cloudwatch"
      access = "proxy"
      jsonData = {
        authType             = "ec2_iam_role"
        defaultRegion        = local.data_source_region
        tracingDatasourceUid = var.xray_enabled ? "aws-xray" : null
        logGroups            = local.cloudwatch_log_groups
        defaultLogGroups     = var.cloudwatch_default_log_group_names
      }
    }] : [],
    local.prometheus_enabled ? [{
      uid    = "amazon-prometheus"
      name   = "Amazon Managed Service for Prometheus"
      type   = "prometheus"
      access = "proxy"
      url    = local.prometheus_query_url
      jsonData = {
        httpMethod    = "POST"
        sigV4Auth     = true
        sigV4AuthType = "ec2_iam_role"
        sigV4Region   = local.prometheus_region
      }
    }] : [],
  )

  managed_data_source_uids = ["aws-xray", "aws-cloudwatch", "amazon-prometheus"]

  # Plugins the data sources need that are not part of Grafana itself. Amazon
  # Managed Grafana installs them only while plugin management is on.
  plugin_ids           = var.xray_enabled ? ["grafana-x-ray-datasource"] : []
  plugin_admin_enabled = var.plugin_admin_enabled || length(local.plugin_ids) > 0
}
