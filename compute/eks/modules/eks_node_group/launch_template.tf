################################################################################
# Launch Template
#
# Created only when the caller customizes anything beyond AMI/instance shape.
# Without it, EKS uses an internally-managed launch template (which we cannot
# modify), so any of: custom user-data, EBS encryption, extra SGs, IMDS
# tweaks, monitoring → triggers creation here.
################################################################################

resource "aws_launch_template" "this" {
  count = local.create_launch_template ? 1 : 0

  name_prefix = "${var.cluster_name}-${var.name}-"
  description = "EKS managed node group launch template for ${var.cluster_name}/${var.name}"

  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : null

  user_data = var.user_data != null ? base64encode(var.user_data) : null

  monitoring {
    enabled = var.detailed_monitoring_enabled
  }

  metadata_options {
    http_tokens                 = var.metadata_http_tokens
    http_put_response_hop_limit = var.metadata_http_put_response_hop_limit
    http_endpoint               = "enabled"
  }

  dynamic "block_device_mappings" {
    for_each = var.disk_size != null || var.disk_type != null || var.ebs_kms_key_arn != null ? [1] : []
    content {
      device_name = "/dev/xvda"
      ebs {
        volume_size           = var.disk_size
        volume_type           = var.disk_type
        iops                  = var.disk_iops
        throughput            = var.disk_throughput
        encrypted             = var.ebs_kms_key_arn != null ? true : null
        kms_key_id            = var.ebs_kms_key_arn
        delete_on_termination = true
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-${var.name}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}
