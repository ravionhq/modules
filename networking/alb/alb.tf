################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal_load_balancer_enabled
  load_balancer_type = "application"
  security_groups    = [module.security_group.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.deletion_protection_enabled
  idle_timeout               = var.idle_timeout
  enable_http2               = var.http2_enabled
  drop_invalid_header_fields = var.invalid_header_drop_enabled
  desync_mitigation_mode     = var.desync_mitigation_mode
  preserve_host_header       = var.host_header_preservation_enabled
  xff_header_processing_mode = var.xff_header_processing_mode
  enable_waf_fail_open       = var.waf_fail_open_enabled

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []
    content {
      bucket  = local.access_logs_bucket_name
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]

}
