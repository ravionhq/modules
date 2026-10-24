mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_regions" {
    defaults = { names = ["us-east-1", "eu-west-1"] }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "ravion-cloudtrail-123456789012-test"
      arn = "arn:aws:s3:::ravion-cloudtrail-123456789012-test"
    }
  }
}

variables {
  regions = ["us-east-1", "eu-west-1"]
}

run "default_multi_region_trail" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.this) == 1 && aws_cloudtrail.this[0].is_multi_region_trail && aws_cloudtrail.this[0].include_global_service_events && aws_cloudtrail.this[0].enable_log_file_validation && aws_cloudtrail.this[0].enable_logging
    error_message = "Exactly one validated multi-Region trail must record events by default."
  }
  assert {
    condition     = one(aws_cloudtrail.this[0].event_selector).read_write_type == "All" && one(aws_cloudtrail.this[0].event_selector).include_management_events && length(one(aws_cloudtrail.this[0].event_selector).data_resource) == 0
    error_message = "Only read and write management events must be selected."
  }
  assert {
    condition     = local.cloudtrail_arn == "arn:aws:cloudtrail:us-east-2:123456789012:trail/ravion-compliance"
    error_message = "The trail must use the runner Region, not the selected compliance Regions."
  }
  assert {
    condition     = !aws_s3_bucket.cloudtrail[0].force_destroy && aws_s3_bucket.cloudtrail[0].bucket_prefix == "ravion-cloudtrail-123456789012-" && aws_s3_bucket.cloudtrail[0].tags["Module"] == "security/compliance"
    error_message = "The bucket must use a unique account-prefixed name, standard tags and safe deletion."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.cloudtrail[0].block_public_acls && aws_s3_bucket_public_access_block.cloudtrail[0].block_public_policy && aws_s3_bucket_public_access_block.cloudtrail[0].ignore_public_acls && aws_s3_bucket_public_access_block.cloudtrail[0].restrict_public_buckets && one(aws_s3_bucket_ownership_controls.cloudtrail[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Audit logs must remain private and bucket-owner enforced."
  }
  assert {
    condition     = one(aws_s3_bucket_versioning.cloudtrail[0].versioning_configuration).status == "Enabled" && one(one(aws_s3_bucket_server_side_encryption_configuration.cloudtrail[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256" && aws_cloudtrail.this[0].kms_key_id == null
    error_message = "Versioning and SSE-S3 must be enabled by default."
  }
  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.cloudtrail[0].rule).expiration).days == 365 && one(one(aws_s3_bucket_lifecycle_configuration.cloudtrail[0].rule).noncurrent_version_expiration).noncurrent_days == 365
    error_message = "Current and noncurrent logs must expire after the configured period."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.cloudtrail[0].policy).Statement[0].Condition.StringEquals["aws:SourceArn"] == local.cloudtrail_arn && jsondecode(aws_s3_bucket_policy.cloudtrail[0].policy).Statement[1].Condition.StringEquals["aws:SourceArn"] == local.cloudtrail_arn && jsondecode(aws_s3_bucket_policy.cloudtrail[0].policy).Statement[1].Condition.StringEquals["s3:x-amz-acl"] == "bucket-owner-full-control" && jsondecode(aws_s3_bucket_policy.cloudtrail[0].policy).Statement[2].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Delivery must be scoped to this trail, require ownership ACLs and deny insecure transport."
  }
}

run "disabled_creates_no_cloudtrail_resources" {
  command = plan
  variables {
    cloudtrail_enabled = false
  }
  assert {
    condition     = length(aws_cloudtrail.this) == 0 && length(aws_s3_bucket.cloudtrail) == 0 && length(aws_s3_bucket_policy.cloudtrail) == 0 && length(aws_s3_bucket_lifecycle_configuration.cloudtrail) == 0 && length(aws_s3_bucket_versioning.cloudtrail) == 0 && length(aws_s3_bucket_public_access_block.cloudtrail) == 0 && length(aws_s3_bucket_ownership_controls.cloudtrail) == 0 && length(aws_s3_bucket_server_side_encryption_configuration.cloudtrail) == 0
    error_message = "Disabling CloudTrail must create no trail or storage resources."
  }
  assert {
    condition     = output.cloudtrail_arn == null && output.cloudtrail_bucket_name == null && output.cloudtrail_bucket_arn == null
    error_message = "CloudTrail outputs must be null when disabled."
  }
}

run "keep_forever" {
  command = plan
  variables {
    cloudtrail_log_retention_days = 0
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.cloudtrail) == 0 && length(aws_s3_bucket.cloudtrail) == 1
    error_message = "Zero retention must disable expiry without disabling log storage."
  }
}

run "custom_retention_and_kms" {
  command = plan
  variables {
    cloudtrail_log_retention_days = 90
    cloudtrail_kms_key_arn        = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
  assert {
    condition     = aws_cloudtrail.this[0].kms_key_id == var.cloudtrail_kms_key_arn && one(one(aws_s3_bucket_server_side_encryption_configuration.cloudtrail[0].rule).apply_server_side_encryption_by_default).kms_master_key_id == var.cloudtrail_kms_key_arn && one(one(aws_s3_bucket_server_side_encryption_configuration.cloudtrail[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "The provided key must encrypt both trail deliveries and bucket objects."
  }
  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.cloudtrail[0].rule).expiration).days == 90 && one(one(aws_s3_bucket_lifecycle_configuration.cloudtrail[0].rule).noncurrent_version_expiration).noncurrent_days == 90
    error_message = "Retention must apply to current and noncurrent versions."
  }
}

run "reject_negative_retention" {
  command = plan
  variables {
    cloudtrail_log_retention_days = -1
  }
  expect_failures = [var.cloudtrail_log_retention_days]
}

run "reject_fractional_retention" {
  command = plan
  variables {
    cloudtrail_log_retention_days = 1.5
  }
  expect_failures = [var.cloudtrail_log_retention_days]
}

run "reject_invalid_kms_key" {
  command = plan
  variables {
    cloudtrail_kms_key_arn = "invalid"
  }
  expect_failures = [var.cloudtrail_kms_key_arn]
}
