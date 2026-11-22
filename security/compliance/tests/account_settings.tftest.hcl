mock_provider "aws" {
  override_data {
    target = data.aws_regions.enabled
    values = {
      names = ["us-east-1", "us-west-2"]
    }
  }
}

variables {
  regions = ["us-west-2", "us-east-1"]
}

run "defaults_turn_every_account_setting_on" {
  command = plan

  assert {
    condition = toset(keys(aws_accessanalyzer_analyzer.this)) == toset(var.regions) && alltrue([
      for region, analyzer in aws_accessanalyzer_analyzer.this :
      analyzer.region == region && analyzer.type == "ACCOUNT"
    ])
    error_message = "Each selected Region must have one account-level external-access analyzer."
  }

  assert {
    condition = toset(keys(aws_ec2_instance_metadata_defaults.this)) == toset(var.regions) && alltrue([
      for region, defaults in aws_ec2_instance_metadata_defaults.this :
      defaults.region == region && defaults.http_tokens == "required"
    ])
    error_message = "Each selected Region must require IMDSv2 by default."
  }

  assert {
    condition = toset(keys(aws_ebs_encryption_by_default.this)) == toset(var.regions) && alltrue([
      for region, encryption in aws_ebs_encryption_by_default.this :
      encryption.region == region && encryption.enabled
    ])
    error_message = "Each selected Region must encrypt new EBS volumes by default."
  }

  assert {
    condition     = length(aws_s3_account_public_access_block.this) == 1
    error_message = "The S3 account public access block is one setting per account, not one per Region."
  }

  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this[0].block_public_acls,
      aws_s3_account_public_access_block.this[0].ignore_public_acls,
      aws_s3_account_public_access_block.this[0].block_public_policy,
      aws_s3_account_public_access_block.this[0].restrict_public_buckets,
    ])
    error_message = "All four S3 public access block settings must be on by default."
  }

  assert {
    condition     = alltrue(values(output.account_settings))
    error_message = "The account_settings output must report every setting as on."
  }
}

run "public_bucket_policies_can_stay_allowed" {
  command = plan

  variables {
    s3_public_policies_blocked = false
  }

  assert {
    condition = (
      aws_s3_account_public_access_block.this[0].block_public_acls &&
      aws_s3_account_public_access_block.this[0].ignore_public_acls &&
      !aws_s3_account_public_access_block.this[0].block_public_policy &&
      !aws_s3_account_public_access_block.this[0].restrict_public_buckets
    )
    error_message = "Turning the policy half off must leave the ACL half on and bucket policies alone."
  }
}

run "every_account_setting_can_be_turned_off" {
  command = plan

  variables {
    access_analyzer_enabled           = false
    imdsv2_default_enabled            = false
    ebs_encryption_by_default_enabled = false
    s3_public_acls_blocked            = false
    s3_public_policies_blocked        = false
  }

  assert {
    condition = (
      length(aws_accessanalyzer_analyzer.this) == 0 &&
      length(aws_ec2_instance_metadata_defaults.this) == 0 &&
      length(aws_ebs_encryption_by_default.this) == 0 &&
      length(aws_s3_account_public_access_block.this) == 0
    )
    error_message = "A setting that is off must not be managed at all, so existing account configuration is left alone."
  }

  assert {
    condition     = length(aws_guardduty_detector.this) == 2 && output.access_analyzer_arns == {}
    error_message = "Turning the account settings off must not affect GuardDuty."
  }
}
