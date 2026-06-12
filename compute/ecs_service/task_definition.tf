################################################################################
# Task Execution Role
################################################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "execution" {
  count = local.create_execution_role ? 1 : 0

  name = "${var.name}-execution"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.tags, {
    Name = "${var.name}-execution"
  })
}

resource "aws_iam_role_policy_attachment" "execution_base" {
  count = local.create_execution_role ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to create/write to the CloudWatch log group used by
# the awslogs driver (awslogs-create-group = true requires logs:CreateLogGroup).
data "aws_iam_policy_document" "execution_logs" {
  count = local.create_execution_role ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name}",
      "arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name}:*",
    ]
  }
}

resource "aws_iam_role_policy" "execution_logs" {
  count = local.create_execution_role ? 1 : 0

  name   = "cloudwatch-logs"
  role   = aws_iam_role.execution[0].id
  policy = data.aws_iam_policy_document.execution_logs[0].json
}

# Additional policy for Secrets Manager and SSM Parameter Store access
data "aws_iam_policy_document" "execution_secrets" {
  count = local.create_execution_role ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = local.create_execution_role ? 1 : 0

  name   = "secrets-access"
  role   = aws_iam_role.execution[0].id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

# Additional execution role policy attachments
resource "aws_iam_role_policy_attachment" "execution_additional" {
  for_each = local.create_execution_role ? toset(var.execution_role_policies) : toset([])

  role       = aws_iam_role.execution[0].name
  policy_arn = each.value
}

################################################################################
# Task Role
################################################################################

resource "aws_iam_role" "task" {
  count = local.create_task_role ? 1 : 0

  name = "${var.name}-task"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.tags, {
    Name = "${var.name}-task"
  })
}

# ECS Exec support
data "aws_iam_policy_document" "task_exec_command" {
  count = local.create_task_role && var.execute_command_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  count = local.create_task_role && var.execute_command_enabled ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task[0].id
  policy = data.aws_iam_policy_document.task_exec_command[0].json
}

# Additional task role policy attachments
resource "aws_iam_role_policy_attachment" "task_additional" {
  for_each = local.create_task_role ? toset(var.task_role_policies) : toset([])

  role       = aws_iam_role.task[0].name
  policy_arn = each.value
}

# Inline task role policies
resource "aws_iam_role_policy" "task_inline" {
  for_each = local.create_task_role ? var.task_role_inline_policies : {}

  name   = each.key
  role   = aws_iam_role.task[0].id
  policy = jsonencode(each.value)
}

################################################################################
# Task Definition
################################################################################

resource "aws_ecs_task_definition" "this" {
  family = var.name

  container_definitions = local.container_definitions

  cpu    = var.task_cpu
  memory = var.task_memory

  network_mode             = var.network_mode
  requires_compatibilities = var.requires_compatibilities

  execution_role_arn = local.create_execution_role ? aws_iam_role.execution[0].arn : var.execution_role_arn
  task_role_arn      = local.create_task_role ? aws_iam_role.task[0].arn : var.task_role_arn

  dynamic "runtime_platform" {
    for_each = var.launch_type == "FARGATE" ? [1] : []
    content {
      operating_system_family = var.runtime_platform.operating_system_family
      cpu_architecture        = var.runtime_platform.cpu_architecture
    }
  }

  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value.name
      host_path = volume.value.host_path

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs_volume_configuration != null ? [volume.value.efs_volume_configuration] : []
        content {
          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = efs_volume_configuration.value.transit_encryption_port

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.authorization_config != null ? [efs_volume_configuration.value.authorization_config] : []
            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = authorization_config.value.iam
            }
          }
        }
      }

      dynamic "docker_volume_configuration" {
        for_each = volume.value.docker_volume_configuration != null ? [volume.value.docker_volume_configuration] : []
        content {
          scope         = docker_volume_configuration.value.scope
          autoprovision = docker_volume_configuration.value.autoprovision
          driver        = docker_volume_configuration.value.driver
          driver_opts   = docker_volume_configuration.value.driver_opts
          labels        = docker_volume_configuration.value.labels
        }
      }

      dynamic "s3files_volume_configuration" {
        for_each = volume.value.s3files_volume_configuration != null ? [volume.value.s3files_volume_configuration] : []
        content {
          file_system_arn         = s3files_volume_configuration.value.file_system_arn
          access_point_arn        = s3files_volume_configuration.value.access_point_arn
          root_directory          = s3files_volume_configuration.value.root_directory
          transit_encryption_port = s3files_volume_configuration.value.transit_encryption_port
        }
      }
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  depends_on = [aws_cloudwatch_log_group.this]

  lifecycle {
    ignore_changes = all
  }
}
