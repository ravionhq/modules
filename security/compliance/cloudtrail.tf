locals {
  cloudtrail_name = "ravion-compliance"
  cloudtrail_arns = {
    for region in local.regions : region => "arn:${data.aws_partition.current.partition}:cloudtrail:${region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
    if var.cloudtrail_enabled
  }
}

resource "aws_cloudtrail" "this" {
  for_each = var.cloudtrail_enabled ? local.regions : toset([])
  region   = each.key

  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  is_multi_region_trail         = false
  include_global_service_events = each.key == "us-east-1"
  enable_log_file_validation    = true
  enable_logging                = true
  kms_key_id                    = var.cloudtrail_kms_key_arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = local.tags

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail,
    aws_s3_bucket_versioning.cloudtrail,
  ]
}
