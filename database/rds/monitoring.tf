################################################################################
# IAM Role for Enhanced Monitoring
################################################################################

resource "aws_iam_role" "monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  name = "${var.name}-rds-enhanced-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-rds-enhanced-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# CloudWatch Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-cpu-utilization"
  alarm_description   = "RDS CPU utilization for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-free-storage-space"
  alarm_description   = "RDS free storage space for ${var.name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_storage_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-database-connections"
  alarm_description   = "RDS database connections for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "read_iops" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-read-iops"
  alarm_description   = "RDS read I/O activity for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "ReadIOPS"
  namespace           = "AWS/RDS"
  period              = max(60, var.cloudwatch_alarm_period)
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_read_iops_threshold
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "write_iops" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-rds-write-iops"
  alarm_description   = "RDS write I/O activity for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "WriteIOPS"
  namespace           = "AWS/RDS"
  period              = max(60, var.cloudwatch_alarm_period)
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_write_iops_threshold
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}
