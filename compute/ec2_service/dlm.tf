################################################################################
# Scheduled Data Volume Snapshots
#
# Amazon Data Lifecycle Manager snapshots the data volume of every
# instance in the group once a day and keeps the newest N snapshots per
# instance. The policy targets instances by their Name tag, which the
# launch template and the Auto Scaling Group already put on every
# instance, so instances launched by earlier module versions are covered
# too. Boot volumes are excluded: application state belongs on the data
# volume or EFS.
#
# Snapshots outlive the instance. With count-based retention, DLM stops
# managing (and never deletes) the snapshots of a terminated instance, so
# a replaced instance's data can still be restored from them.
################################################################################

locals {
  data_volume_snapshots_enabled = var.data_volume_creation_enabled && var.data_volume_snapshots_enabled

  # Daily snapshot start time (UTC). DLM starts the snapshots within an
  # hour of this time.
  data_volume_snapshot_time = "03:00"
}

resource "aws_iam_role" "dlm" {
  count = local.data_volume_snapshots_enabled ? 1 : 0

  name = "${var.name}-dlm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count = local.data_volume_snapshots_enabled ? 1 : 0

  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "data_volume" {
  count = local.data_volume_snapshots_enabled ? 1 : 0

  description        = "Daily data volume snapshots for the ${var.name} EC2 service"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    policy_type    = "EBS_SNAPSHOT_MANAGEMENT"
    resource_types = ["INSTANCE"]

    target_tags = {
      Name = var.name
    }

    parameters {
      exclude_boot_volume = true
    }

    schedule {
      name      = "Daily data volume snapshots"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = [local.data_volume_snapshot_time]
      }

      retain_rule {
        count = var.data_volume_snapshot_retention_count
      }

      tags_to_add = {
        "ravion:snapshot-type" = "scheduled"
        "ravion:service"       = var.name
      }

      variable_tags = {
        "ravion:instance-id" = "$(instance-id)"
      }
    }
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.dlm]
}
