################################################################################
# Scheduled Auto Stop
################################################################################

resource "aws_iam_role" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0

  name = "${var.name}-dev-box-stop"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0

  name = "stop-instance"
  role = aws_iam_role.auto_stop[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StopDevBox"
        Effect   = "Allow"
        Action   = "ec2:StopInstances"
        Resource = aws_instance.this.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0

  name                         = "${var.name}-dev-box-stop"
  description                  = "Stops dev box ${var.name}."
  schedule_expression          = var.auto_stop_schedule_expression
  schedule_expression_timezone = var.auto_stop_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${data.aws_partition.current.partition}:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.auto_stop[0].arn
    input    = jsonencode({ InstanceIds = [aws_instance.this.id] })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
