################################################################################
# IAM Role for Enhanced Monitoring
################################################################################

resource "aws_iam_role" "monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  name = "${var.name}-aurora-enhanced-monitoring"

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
    Name = "${var.name}-aurora-enhanced-monitoring"
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

  alarm_name          = "${var.name}-aurora-cpu-utilization"
  alarm_description   = "Aurora cluster CPU utilization for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-aurora-freeable-memory"
  alarm_description   = "Aurora cluster freeable memory for ${var.name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-aurora-database-connections"
  alarm_description   = "Aurora cluster database connections for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "read_iops" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-aurora-read-iops"
  alarm_description   = "Aurora cluster read I/O activity for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "ReadIOPS"
  namespace           = "AWS/RDS"
  period              = max(60, var.cloudwatch_alarm_period)
  statistic           = "Maximum"
  threshold           = var.cloudwatch_alarm_read_iops_threshold
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "write_iops" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-aurora-write-iops"
  alarm_description   = "Aurora cluster write I/O activity for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "WriteIOPS"
  namespace           = "AWS/RDS"
  period              = max(60, var.cloudwatch_alarm_period)
  statistic           = "Maximum"
  threshold           = var.cloudwatch_alarm_write_iops_threshold
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}

# Aurora storage automatically grows. MySQL publishes remaining volume space;
# PostgreSQL exposes used volume bytes instead. Both work with Serverless v2.
resource "aws_cloudwatch_metric_alarm" "cluster_storage" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = local.is_mysql ? "${var.name}-aurora-free-storage-space" : "${var.name}-aurora-volume-bytes-used"
  alarm_description   = "Aurora cluster storage capacity for ${var.name}"
  comparison_operator = local.is_mysql ? "LessThanThreshold" : "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = local.is_mysql ? "AuroraVolumeBytesLeftTotal" : "VolumeBytesUsed"
  namespace           = "AWS/RDS"
  period              = max(300, var.cloudwatch_alarm_period)
  statistic           = local.is_mysql ? "Minimum" : "Maximum"
  threshold           = local.is_mysql ? var.cloudwatch_alarm_storage_threshold : var.cloudwatch_alarm_volume_bytes_used_threshold
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions
  tags          = local.tags
}
