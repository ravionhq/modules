################################################################################
# IAM Roles
#
# The execution role lets ECS pull the image and write the collector's own
# logs. The task role is what the collector calls AWS with: X-Ray writes, plus
# the metric log group or the Prometheus workspace while metrics go there, and
# the OTLP log group while logs are enabled.
################################################################################

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  description        = "ECS task execution role for OpenTelemetry collector ${var.name}."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  description        = "Task role for OpenTelemetry collector ${var.name}."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

# X-Ray has no resource-level permissions for these actions.
data "aws_iam_policy_document" "xray" {
  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "xray" {
  name   = "xray-write"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.xray.json
}

data "aws_iam_policy_document" "metrics" {
  count = local.metrics_destination == "cloudwatch" ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.metrics[0].arn,
      "${aws_cloudwatch_log_group.metrics[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "metrics" {
  count = local.metrics_destination == "cloudwatch" ? 1 : 0

  name   = "cloudwatch-metrics"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.metrics[0].json
}

data "aws_iam_policy_document" "prometheus" {
  count = local.metrics_destination == "prometheus" ? 1 : 0

  statement {
    actions   = ["aps:RemoteWrite"]
    resources = [var.prometheus_workspace_arn]
  }
}

resource "aws_iam_role_policy" "prometheus" {
  count = local.metrics_destination == "prometheus" ? 1 : 0

  name   = "prometheus-remote-write"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.prometheus[0].json
}

data "aws_iam_policy_document" "logs" {
  count = var.logs_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.otlp_logs[0].arn,
      "${aws_cloudwatch_log_group.otlp_logs[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "logs" {
  count = var.logs_enabled ? 1 : 0

  name   = "cloudwatch-otlp-logs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.logs[0].json
}
