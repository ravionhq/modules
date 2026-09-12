################################################################################
# Grafana read role (optional)
#
# An IAM role Amazon Managed Grafana can assume to read this cluster's
# telemetry: PromQL against the AMP workspace, Logs Insights against the
# Container Insights log groups. Read-only, and the two halves are independent —
# with metrics off the role still carries the log grants.
#
# Deliberately NOT an AMG workspace. Provisioning one requires IAM Identity
# Center or SAML wiring that is organization-scoped; creating that from a
# per-cluster module puts an org-level blast radius behind a cluster-level
# toggle. The role is the part that is genuinely per-cluster, and the README
# carries the datasource configuration that consumes it.
#
# The trust is narrowed with aws:SourceAccount, so it names the account whose
# Grafana workspaces may assume the role rather than the Grafana service at
# large — the confused-deputy guard AWS documents for service principals.
################################################################################

locals {
  grafana_source_account_id = coalesce(var.grafana_source_account_id, data.aws_caller_identity.current.account_id)

  # The add-on's two Container Insights groups plus the cluster's control-plane
  # logs: everything the cluster module's Logs tab points at.
  grafana_log_group_arns = [
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/containerinsights/${var.cluster_name}/*",
    "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.cluster_name}/cluster:*",
  ]
}

data "aws_iam_policy_document" "grafana_read" {
  count = var.grafana_role_creation_enabled ? 1 : 0

  # Only rendered when there is a workspace to point at, so the role is still
  # useful for logs on a cluster with metrics off.
  dynamic "statement" {
    for_each = local.amp_enabled ? [1] : []

    content {
      sid    = "QueryPrometheusWorkspace"
      effect = "Allow"
      actions = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      resources = [local.amp_workspace_arn]
    }
  }

  statement {
    sid    = "ReadClusterLogGroups"
    effect = "Allow"
    actions = [
      "logs:StartQuery",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = local.grafana_log_group_arns
  }

  # IAM defines no resource type for these: they are session- and
  # account-scoped, and scoping them to a log group ARN would deny every call.
  # StartQuery above is what actually gates which groups can be read.
  statement {
    sid    = "ReadQueryResults"
    effect = "Allow"
    actions = [
      "logs:GetQueryResults",
      "logs:StopQuery",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

module "grafana_role" {
  count = var.grafana_role_creation_enabled ? 1 : 0

  source = "../../../security/iam"

  name        = "${var.cluster_name}-grafana-read"
  description = "Grafana read access to the AMP workspace and Container Insights log groups for ${var.cluster_name}"

  trusted_services = ["grafana.amazonaws.com"]

  assume_role_conditions = [{
    test     = "StringEquals"
    variable = "aws:SourceAccount"
    values   = [local.grafana_source_account_id]
  }]

  inline_policies = {
    "telemetry-read" = data.aws_iam_policy_document.grafana_read[0].json
  }

  tags = local.tags
}
