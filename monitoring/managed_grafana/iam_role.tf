################################################################################
# Workspace Role
#
# The role Grafana reads AWS data with. It can read, never write: CloudWatch
# metrics and logs and X-Ray traces while those data sources are on, and the
# one Prometheus workspace while it is a data source.
################################################################################

data "aws_iam_policy_document" "grafana_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:grafana:${local.region}:${data.aws_caller_identity.current.account_id}:/workspaces/*"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-grafana"
  description        = "Role Amazon Managed Grafana workspace ${var.name} reads AWS data with."
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json

  tags = local.tags
}

# CloudWatch and CloudWatch Logs reads have no resource-level scoping that fits
# a dashboard: any metric or log group in the account may be charted.
data "aws_iam_policy_document" "cloudwatch" {
  count = var.cloudwatch_enabled ? 1 : 0

  statement {
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "tag:GetResources",
      "oam:ListSinks",
      "oam:ListAttachedLinks",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  count = var.cloudwatch_enabled ? 1 : 0

  name   = "cloudwatch-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.cloudwatch[0].json
}

# X-Ray reads have no resource-level permissions.
data "aws_iam_policy_document" "xray" {
  count = var.xray_enabled ? 1 : 0

  statement {
    actions = [
      "xray:BatchGetTraces",
      "xray:GetTraceSummaries",
      "xray:GetTraceGraph",
      "xray:GetGroups",
      "xray:GetTimeSeriesServiceStatistics",
      "xray:GetInsightSummaries",
      "xray:GetInsight",
      "xray:GetServiceGraph",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "xray" {
  count = var.xray_enabled ? 1 : 0

  name   = "xray-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.xray[0].json
}

data "aws_iam_policy_document" "prometheus" {
  count = local.prometheus_enabled ? 1 : 0

  statement {
    actions = [
      "aps:QueryMetrics",
      "aps:GetSeries",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
    ]
    resources = [local.prometheus_workspace_arn]
  }
}

resource "aws_iam_role_policy" "prometheus" {
  count = local.prometheus_enabled ? 1 : 0

  name   = "prometheus-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.prometheus[0].json
}
