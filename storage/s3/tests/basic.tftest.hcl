################################################################################
# S3 Module Unit Tests
################################################################################

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
      id  = "127311923021"
    }
  }
}

#-------------------------------------------------------------------------------
# Name Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid bucket name - basic
run "test_name_validation_valid_basic" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = var.name == "my-test-bucket"
    error_message = "Valid bucket name should be accepted."
  }
}

# Test: Valid bucket name - with numbers
run "test_name_validation_valid_with_numbers" {
  command = plan

  variables {
    name = "bucket-123-test"
  }

  assert {
    condition     = var.name == "bucket-123-test"
    error_message = "Valid bucket name with numbers should be accepted."
  }
}

# Test: Valid bucket name - with periods
run "test_name_validation_valid_with_periods" {
  command = plan

  variables {
    name = "my.test.bucket"
  }

  assert {
    condition     = var.name == "my.test.bucket"
    error_message = "Valid bucket name with periods should be accepted."
  }
}

# Test: Valid bucket name - minimum length (3 characters)
run "test_name_validation_valid_min_length" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = length(var.name) == 3
    error_message = "Valid bucket name with minimum length (3 characters) should be accepted."
  }
}

# Test: Valid bucket name - starting with number
run "test_name_validation_valid_starts_with_number" {
  command = plan

  variables {
    name = "123-bucket"
  }

  assert {
    condition     = var.name == "123-bucket"
    error_message = "Valid bucket name starting with number should be accepted."
  }
}

# Test: Invalid bucket name - too short (less than 3 characters)
run "test_name_validation_min_length" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - too long (more than 63 characters)
run "test_name_validation_max_length" {
  command = plan

  variables {
    name = "this-bucket-name-is-way-too-long-and-exceeds-the-sixty-three-character-limit-set-by-aws"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains uppercase letters
run "test_name_validation_invalid_uppercase" {
  command = plan

  variables {
    name = "My-Test-Bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains underscores
run "test_name_validation_invalid_underscore" {
  command = plan

  variables {
    name = "my_test_bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - starts with hyphen
run "test_name_validation_hyphen_start" {
  command = plan

  variables {
    name = "-my-bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - ends with hyphen
run "test_name_validation_hyphen_end" {
  command = plan

  variables {
    name = "my-bucket-"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - starts with period
run "test_name_validation_period_start" {
  command = plan

  variables {
    name = ".my-bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - ends with period
run "test_name_validation_period_end" {
  command = plan

  variables {
    name = "my-bucket."
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - consecutive periods
run "test_name_validation_consecutive_periods" {
  command = plan

  variables {
    name = "my..bucket"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - formatted as IP address
run "test_name_validation_ip_address" {
  command = plan

  variables {
    name = "192.168.1.1"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid bucket name - contains special characters
run "test_name_validation_invalid_special_chars" {
  command = plan

  variables {
    name = "my@bucket!"
  }

  expect_failures = [
    var.name,
  ]
}

#-------------------------------------------------------------------------------
# Force Destroy Tests
#-------------------------------------------------------------------------------

# Test: force_destroy defaults to false
run "test_force_destroy_default_false" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = var.force_destroy_enabled == false
    error_message = "force_destroy should default to false."
  }
}

# Test: force_destroy can be set to true
run "test_force_destroy_can_be_true" {
  command = plan

  variables {
    name                  = "test-bucket"
    force_destroy_enabled = true
  }

  assert {
    condition     = var.force_destroy_enabled == true
    error_message = "force_destroy should be able to be set to true."
  }
}

#-------------------------------------------------------------------------------
# Tags Tests
#-------------------------------------------------------------------------------

# Test: tags default to empty map
run "test_tags_default_empty" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(var.tags) == 0
    error_message = "tags should default to an empty map."
  }
}

# Test: tags can be provided
run "test_tags_can_be_provided" {
  command = plan

  variables {
    name = "test-bucket"
    tags = {
      Environment = "test"
      Project     = "s3-module"
    }
  }

  assert {
    condition     = var.tags["Environment"] == "test"
    error_message = "Custom tags should be accepted."
  }
}

#-------------------------------------------------------------------------------
# S3 Bucket Resource Tests
#-------------------------------------------------------------------------------

# Test: bucket is created with correct name
run "test_bucket_creation_with_name" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "my-test-bucket"
    error_message = "Bucket should be created with the specified name."
  }
}

# Test: bucket force_destroy defaults to false
run "test_bucket_force_destroy_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "Bucket force_destroy should default to false."
  }
}

# Test: bucket force_destroy can be set to true
run "test_bucket_force_destroy_true" {
  command = plan

  variables {
    name                  = "test-bucket"
    force_destroy_enabled = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "Bucket force_destroy should be set to true when specified."
  }
}

# Test: bucket has default tags merged
run "test_bucket_default_tags" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["ManagedBy"] == "terraform"
    error_message = "Bucket should have ManagedBy default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Module"] == "storage/s3"
    error_message = "Bucket should have Module default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "test-bucket"
    error_message = "Bucket should have Name tag matching bucket name."
  }
}

# Test: bucket has custom tags merged with defaults
run "test_bucket_custom_tags_merged" {
  command = plan

  variables {
    name = "test-bucket"
    tags = {
      Environment = "production"
      Team        = "platform"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["ManagedBy"] == "terraform"
    error_message = "Bucket should retain ManagedBy default tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Environment"] == "production"
    error_message = "Bucket should have custom Environment tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Team"] == "platform"
    error_message = "Bucket should have custom Team tag."
  }
}

#-------------------------------------------------------------------------------
# Public Access Block Tests
#-------------------------------------------------------------------------------

# Test: public access block defaults - all settings enabled
run "test_public_access_block_defaults" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "block_public_acls should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "block_public_policy should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == true
    error_message = "ignore_public_acls should default to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    error_message = "restrict_public_buckets should default to true."
  }
}

# Test: public access block can disable block_public_acls
run "test_public_access_block_disable_block_public_acls" {
  command = plan

  variables {
    name              = "test-bucket"
    block_public_acls = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == false
    error_message = "block_public_acls should be false when set."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "block_public_policy should remain true."
  }
}

# Test: public access block can disable block_public_policy
run "test_public_access_block_disable_block_public_policy" {
  command = plan

  variables {
    name                = "test-bucket"
    block_public_policy = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == false
    error_message = "block_public_policy should be false when set."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "block_public_acls should remain true."
  }
}

# Test: public access block can disable ignore_public_acls
run "test_public_access_block_disable_ignore_public_acls" {
  command = plan

  variables {
    name               = "test-bucket"
    ignore_public_acls = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == false
    error_message = "ignore_public_acls should be false when set."
  }
}

# Test: public access block can disable restrict_public_buckets
run "test_public_access_block_disable_restrict_public_buckets" {
  command = plan

  variables {
    name                    = "test-bucket"
    restrict_public_buckets = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == false
    error_message = "restrict_public_buckets should be false when set."
  }
}

# Test: public access block can disable all settings
run "test_public_access_block_all_disabled" {
  command = plan

  variables {
    name                    = "test-bucket"
    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == false
    error_message = "block_public_acls should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == false
    error_message = "block_public_policy should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == false
    error_message = "ignore_public_acls should be false."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == false
    error_message = "restrict_public_buckets should be false."
  }
}

# Test: public access block references correct bucket
run "test_public_access_block_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.bucket == aws_s3_bucket.this.id
    error_message = "Public access block should reference the correct bucket."
  }
}

#-------------------------------------------------------------------------------
# Server-Side Encryption Tests
#-------------------------------------------------------------------------------

# Test: encryption uses SSE-S3 (AES256) by default
run "test_encryption_sse_s3_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].sse_algorithm) == "AES256"
    error_message = "Encryption should use SSE-S3 (AES256) by default."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].kms_master_key_id) == null
    error_message = "KMS key should be null when using SSE-S3."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].blocked_encryption_types) == tolist(["SSE-C"])
    error_message = "SSE-C uploads should be blocked."
  }
}

# Test: encryption uses SSE-KMS when KMS key is provided
run "test_encryption_sse_kms_with_key" {
  command = plan

  variables {
    name       = "test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].sse_algorithm) == "aws:kms"
    error_message = "Encryption should use SSE-KMS when KMS key is provided."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].apply_server_side_encryption_by_default[0].kms_master_key_id) == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "KMS key should be set when provided."
  }
}

# Test: bucket key is enabled by default for SSE-KMS
run "test_encryption_bucket_key_enabled_default" {
  command = plan

  variables {
    name       = "test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].bucket_key_enabled) == true
    error_message = "Bucket key should be enabled by default for SSE-KMS."
  }
}

# Test: bucket key can be disabled for SSE-KMS
run "test_encryption_bucket_key_disabled" {
  command = plan

  variables {
    name               = "test-bucket"
    kms_key_id         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    bucket_key_enabled = false
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule[*].bucket_key_enabled) == false
    error_message = "Bucket key should be disabled when set to false."
  }
}

# Test: encryption references correct bucket
run "test_encryption_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.bucket == aws_s3_bucket.this.id
    error_message = "Encryption configuration should reference the correct bucket."
  }
}

#-------------------------------------------------------------------------------
# Versioning Tests
#-------------------------------------------------------------------------------

# Test: versioning is disabled by default
run "test_versioning_disabled_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Disabled"
    error_message = "Versioning should be disabled by default."
  }
}

# Test: versioning can be enabled
run "test_versioning_enabled" {
  command = plan

  variables {
    name               = "test-bucket"
    versioning_enabled = true
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled when versioning_enabled is true."
  }
}

# Test: versioning references correct bucket
run "test_versioning_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.bucket == aws_s3_bucket.this.id
    error_message = "Versioning configuration should reference the correct bucket."
  }
}

# Test: versioning_enabled variable defaults to false
run "test_versioning_enabled_variable_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = var.versioning_enabled == false
    error_message = "versioning_enabled variable should default to false."
  }
}

#-------------------------------------------------------------------------------
# Region Tests
#-------------------------------------------------------------------------------

# Test: the bucket and its configuration are managed in the selected region,
# not the provider's
run "test_region_is_where_the_bucket_is_managed" {
  command = plan

  variables {
    name                   = "test-bucket"
    region                 = "eu-west-1"
    versioning_enabled     = true
    requester_pays_enabled = true
    policy_templates       = ["deny_insecure_transport"]
  }

  assert {
    condition     = aws_s3_bucket.this.region == "eu-west-1"
    error_message = "The bucket should be created in the selected region."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.region == "eu-west-1",
      aws_s3_bucket_server_side_encryption_configuration.this.region == "eu-west-1",
      aws_s3_bucket_versioning.this.region == "eu-west-1",
      aws_s3_bucket_request_payment_configuration.this[0].region == "eu-west-1",
      aws_s3_bucket_policy.this[0].region == "eu-west-1",
    ])
    error_message = "The bucket's configuration should be managed in the bucket's region."
  }
}

#-------------------------------------------------------------------------------
# Requester Pays Tests
#-------------------------------------------------------------------------------

# Test: the bucket owner pays by default, with no request payment configuration
run "test_requester_pays_disabled_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_request_payment_configuration.this) == 0
    error_message = "No request payment configuration should be created by default."
  }
}

# Test: Requester Pays can be enabled
run "test_requester_pays_enabled" {
  command = plan

  variables {
    name                   = "test-bucket"
    requester_pays_enabled = true
  }

  assert {
    condition     = length(aws_s3_bucket_request_payment_configuration.this) == 1
    error_message = "A request payment configuration should be created when requester_pays_enabled is true."
  }

  assert {
    condition     = aws_s3_bucket_request_payment_configuration.this[0].payer == "Requester"
    error_message = "The requester should pay when requester_pays_enabled is true."
  }

  assert {
    condition     = aws_s3_bucket_request_payment_configuration.this[0].bucket == aws_s3_bucket.this.id
    error_message = "The request payment configuration should reference the bucket."
  }
}

#-------------------------------------------------------------------------------
# CORS Configuration Tests
#-------------------------------------------------------------------------------

# Test: no CORS configuration when rules are empty
run "test_cors_rules_empty" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(var.cors_rules) == 0
    error_message = "cors_rules should default to empty list."
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 0
    error_message = "CORS configuration should not be created when rules are empty."
  }
}

# Test: CORS configuration created when rules provided
run "test_cors_rules_single_rule" {
  command = plan

  variables {
    name = "test-bucket"
    cors_rules = [
      {
        id              = "app"
        allowed_methods = ["GET", "PUT"]
        allowed_origins = ["https://app.example.com"]
        allowed_headers = ["*"]
        expose_headers  = ["ETag"]
        max_age_seconds = 3000
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 1
    error_message = "CORS configuration should be created when rules are provided."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).id == "app"
    error_message = "CORS rule should have the correct id."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).allowed_methods == toset(["GET", "PUT"])
    error_message = "CORS rule should have the correct allowed methods."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).allowed_origins == toset(["https://app.example.com"])
    error_message = "CORS rule should have the correct allowed origins."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).allowed_headers == toset(["*"])
    error_message = "CORS rule should have the correct allowed headers."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).expose_headers == toset(["ETag"])
    error_message = "CORS rule should have the correct exposed headers."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).max_age_seconds == 3000
    error_message = "CORS rule should have the correct max age."
  }
}

# Test: multiple CORS rules are supported
run "test_cors_rules_multiple" {
  command = plan

  variables {
    name = "test-bucket"
    cors_rules = [
      {
        allowed_methods = ["GET"]
        allowed_origins = ["https://app.example.com"]
      },
      {
        allowed_methods = ["POST"]
        allowed_origins = ["https://admin.example.com"]
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this[0].cors_rule) == 2
    error_message = "CORS configuration should include two rules."
  }
}

# Test: CORS configuration references correct bucket
run "test_cors_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
    cors_rules = [
      {
        allowed_methods = ["GET"]
        allowed_origins = ["https://app.example.com"]
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_cors_configuration.this[0].bucket == aws_s3_bucket.this.id
    error_message = "CORS configuration should reference the correct bucket."
  }
}

# Test: invalid CORS method rejected
run "test_cors_invalid_method" {
  command = plan

  variables {
    name = "test-bucket"
    cors_rules = [
      {
        allowed_methods = ["OPTIONS"]
        allowed_origins = ["https://app.example.com"]
      }
    ]
  }

  expect_failures = [
    var.cors_rules,
  ]
}

# Test: empty CORS origins rejected
run "test_cors_empty_origins" {
  command = plan

  variables {
    name = "test-bucket"
    cors_rules = [
      {
        allowed_methods = ["GET"]
        allowed_origins = []
      }
    ]
  }

  expect_failures = [
    var.cors_rules,
  ]
}

# Test: empty CORS methods rejected
run "test_cors_empty_methods" {
  command = plan

  variables {
    name = "test-bucket"
    cors_rules = [
      {
        allowed_methods = []
        allowed_origins = ["https://app.example.com"]
      }
    ]
  }

  expect_failures = [
    var.cors_rules,
  ]
}

#-------------------------------------------------------------------------------
# Lifecycle Configuration Tests
#-------------------------------------------------------------------------------

# Test: no lifecycle configuration when rules are empty
run "test_lifecycle_rules_empty" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(var.lifecycle_rules) == 0
    error_message = "lifecycle_rules should default to empty list."
  }
}

# Test: lifecycle configuration created when rules provided
run "test_lifecycle_rules_single_expiration" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id      = "expire-old-objects"
        enabled = true
        expiration = {
          days = 90
        }
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 1
    error_message = "Lifecycle configuration should be created when rules are provided."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].id == "expire-old-objects"
    error_message = "Lifecycle rule should have the correct id."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].status == "Enabled"
    error_message = "Lifecycle rule should be enabled."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration[0].days == 90
    error_message = "Lifecycle rule should have correct expiration days."
  }
}

# Test: lifecycle rule can be disabled
run "test_lifecycle_rule_disabled" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id      = "disabled-rule"
        enabled = false
        expiration = {
          days = 30
        }
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].status == "Disabled"
    error_message = "Lifecycle rule should be disabled when enabled is false."
  }
}

# Test: lifecycle rule with prefix filter
run "test_lifecycle_rule_with_prefix" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id     = "logs-expiration"
        prefix = "logs/"
        expiration = {
          days = 30
        }
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter[0].prefix == "logs/"
    error_message = "Lifecycle rule should have correct prefix filter."
  }
}

# Test: lifecycle rule with transitions
run "test_lifecycle_rule_with_transitions" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = "archive-old-objects"
        transitions = [
          {
            days          = 30
            storage_class = "STANDARD_IA"
          },
          {
            days          = 90
            storage_class = "GLACIER"
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].transition) == 2
    error_message = "Lifecycle rule should have two transitions."
  }

  assert {
    condition     = anytrue([for t in aws_s3_bucket_lifecycle_configuration.this[0].rule[0].transition : t.storage_class == "STANDARD_IA"])
    error_message = "Should have a transition to STANDARD_IA."
  }

  assert {
    condition     = anytrue([for t in aws_s3_bucket_lifecycle_configuration.this[0].rule[0].transition : t.storage_class == "GLACIER"])
    error_message = "Should have a transition to GLACIER."
  }
}

# Test: lifecycle rule with abort incomplete multipart upload
run "test_lifecycle_rule_abort_incomplete_multipart" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id                                     = "cleanup-incomplete-uploads"
        abort_incomplete_multipart_upload_days = 7
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Abort incomplete multipart upload should be set to 7 days."
  }
}

# Test: lifecycle rule with noncurrent version expiration
run "test_lifecycle_rule_noncurrent_version_expiration" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = "expire-old-versions"
        noncurrent_version_expiration = {
          noncurrent_days = 90
        }
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Noncurrent version expiration should be set to 90 days."
  }
}

# Test: lifecycle rule with noncurrent version transitions
run "test_lifecycle_rule_noncurrent_version_transitions" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = "archive-old-versions"
        noncurrent_version_transitions = [
          {
            noncurrent_days = 30
            storage_class   = "GLACIER"
          }
        ]
      }
    ]
  }

  assert {
    condition     = anytrue([for t in aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_transition : t.storage_class == "GLACIER"])
    error_message = "Noncurrent version transition should be to GLACIER."
  }
}

# Test: multiple lifecycle rules
run "test_multiple_lifecycle_rules" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id     = "logs-expiration"
        prefix = "logs/"
        expiration = {
          days = 30
        }
      },
      {
        id     = "archives-transition"
        prefix = "archives/"
        transitions = [
          {
            days          = 60
            storage_class = "GLACIER"
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule) == 2
    error_message = "Should have two lifecycle rules."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].id == "logs-expiration"
    error_message = "First rule should be logs-expiration."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[1].id == "archives-transition"
    error_message = "Second rule should be archives-transition."
  }
}

# Test: lifecycle rule enabled defaults to true
run "test_lifecycle_rule_enabled_default" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = "default-enabled-rule"
        expiration = {
          days = 30
        }
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].status == "Enabled"
    error_message = "Lifecycle rule should be enabled by default."
  }
}

# Test: lifecycle configuration references correct bucket
run "test_lifecycle_bucket_reference" {
  command = plan

  variables {
    name = "my-test-bucket"
    lifecycle_rules = [
      {
        id = "test-rule"
        expiration = {
          days = 30
        }
      }
    ]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].bucket == aws_s3_bucket.this.id
    error_message = "Lifecycle configuration should reference the correct bucket."
  }
}

# Test: invalid storage class in transitions rejected
run "test_lifecycle_invalid_storage_class" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = "invalid-rule"
        transitions = [
          {
            days          = 30
            storage_class = "INVALID_CLASS"
          }
        ]
      }
    ]
  }

  expect_failures = [
    var.lifecycle_rules,
  ]
}

# Test: empty rule id rejected
run "test_lifecycle_empty_rule_id" {
  command = plan

  variables {
    name = "test-bucket"
    lifecycle_rules = [
      {
        id = ""
        expiration = {
          days = 30
        }
      }
    ]
  }

  expect_failures = [
    var.lifecycle_rules,
  ]
}

#-------------------------------------------------------------------------------
# Policy Template Tests
#-------------------------------------------------------------------------------

# Test: policy_templates defaults to empty list
run "test_policy_templates_default_empty" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(var.policy_templates) == 0
    error_message = "policy_templates should default to empty list."
  }
}

# Test: deny_insecure_transport template produces valid statements
run "test_policy_template_deny_insecure_transport" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 1
    error_message = "deny_insecure_transport template should produce 1 statement."
  }

  assert {
    condition     = local.policy_template_statements[0].Sid == "DenyInsecureTransport"
    error_message = "deny_insecure_transport statement should have correct Sid."
  }

  assert {
    condition     = local.policy_template_statements[0].Effect == "Deny"
    error_message = "deny_insecure_transport statement should have Deny effect."
  }

  assert {
    condition     = local.policy_template_statements[0].Action == "s3:*"
    error_message = "deny_insecure_transport statement should deny all S3 actions."
  }
}

# Test: alb_access_logs template produces valid statements
run "test_policy_template_alb_access_logs" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["alb_access_logs"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 3
    error_message = "alb_access_logs template should produce 3 statements."
  }

  assert {
    condition     = local.policy_template_statements[0].Sid == "AllowELBRootAccount"
    error_message = "First statement should be AllowELBRootAccount."
  }

  assert {
    condition     = local.policy_template_statements[1].Sid == "AllowELBLogDelivery"
    error_message = "Second statement should be AllowELBLogDelivery."
  }

  assert {
    condition     = local.policy_template_statements[2].Sid == "AllowELBLogDeliveryAclCheck"
    error_message = "Third statement should be AllowELBLogDeliveryAclCheck."
  }
}

# Test: nlb_access_logs template produces valid statements
run "test_policy_template_nlb_access_logs" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["nlb_access_logs"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 2
    error_message = "nlb_access_logs template should produce 2 statements."
  }

  assert {
    condition     = local.policy_template_statements[0].Sid == "AllowNLBLogDelivery"
    error_message = "First statement should be AllowNLBLogDelivery."
  }

  assert {
    condition     = local.policy_template_statements[1].Sid == "AllowNLBLogDeliveryAclCheck"
    error_message = "Second statement should be AllowNLBLogDeliveryAclCheck."
  }
}

# Test: vpc_flow_logs template produces valid statements
run "test_policy_template_vpc_flow_logs" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["vpc_flow_logs"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 2
    error_message = "vpc_flow_logs template should produce 2 statements."
  }

  assert {
    condition     = local.policy_template_statements[0].Sid == "AWSLogDeliveryAclCheck"
    error_message = "First statement should be AWSLogDeliveryAclCheck."
  }

  assert {
    condition     = local.policy_template_statements[1].Sid == "AWSLogDeliveryWrite"
    error_message = "Second statement should be AWSLogDeliveryWrite."
  }
}

# Test: cloudfront_oac_read template produces valid statements
run "test_policy_template_cloudfront_oac_read" {
  command = plan

  variables {
    name                         = "test-bucket"
    policy_templates             = ["cloudfront_oac_read"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 1
    error_message = "cloudfront_oac_read template should produce 1 statement."
  }

  assert {
    condition     = local.policy_template_statements[0].Sid == "AllowCloudFrontOACRead"
    error_message = "cloudfront_oac_read statement should have correct Sid."
  }

  assert {
    condition     = local.policy_template_statements[0].Principal.Service == "cloudfront.amazonaws.com"
    error_message = "cloudfront_oac_read statement should use the CloudFront service principal."
  }

  assert {
    condition     = length(local.policy_template_statements[0].Condition.StringEquals["aws:SourceArn"]) == 1 && contains(local.policy_template_statements[0].Condition.StringEquals["aws:SourceArn"], "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE")
    error_message = "cloudfront_oac_read statement should scope access to distribution ARNs."
  }
}

# Test: cloudfront_oac_read requires distribution ARNs
run "test_policy_template_cloudfront_oac_read_requires_arns" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["cloudfront_oac_read"]
  }

  expect_failures = [
    var.policy_templates,
  ]
}

# Test: multiple policy templates can be combined
run "test_policy_templates_combined" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport", "alb_access_logs"]
  }

  assert {
    condition     = length(local.policy_template_statements) == 4
    error_message = "Combined templates should produce 4 statements (1 + 3)."
  }
}

# Test: policy template uses correct account_id from data source
run "test_policy_template_uses_account_id" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["alb_access_logs"]
  }

  assert {
    condition     = local.account_id == "123456789012"
    error_message = "Policy template should use account_id from data source."
  }
}

# Test: policy template uses correct region from data source
run "test_policy_template_uses_region" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["vpc_flow_logs"]
  }

  assert {
    condition     = local.region == "us-east-1"
    error_message = "Policy template should use region id from data source."
  }
}

# Test: policy template uses correct ELB service account ARN
run "test_policy_template_uses_elb_service_account" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["alb_access_logs"]
  }

  assert {
    condition     = local.elb_service_arn == "arn:aws:iam::127311923021:root"
    error_message = "Policy template should use ELB service account ARN from data source."
  }
}

# Test: invalid policy template is rejected
run "test_policy_template_invalid_rejected" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["unknown_template"]
  }

  expect_failures = [
    var.policy_templates,
  ]
}

# Test: multiple valid templates accepted
run "test_policy_templates_all_valid" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport", "alb_access_logs", "nlb_access_logs", "vpc_flow_logs", "cloudfront_oac_read"]
    cloudfront_distribution_arns = [
      "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
    ]
  }

  assert {
    condition     = length(local.policy_template_statements) == 9
    error_message = "All five templates combined should produce 9 statements (1 + 3 + 2 + 2 + 1)."
  }
}

# Test: mix of valid and invalid templates rejected
run "test_policy_templates_mixed_invalid" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport", "invalid_template"]
  }

  expect_failures = [
    var.policy_templates,
  ]
}

#-------------------------------------------------------------------------------
# Custom Policy Tests
#-------------------------------------------------------------------------------

# Test: custom_policy defaults to null
run "test_custom_policy_default_null" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = var.custom_policy == null
    error_message = "custom_policy should default to null."
  }
}

# Test: valid custom_policy JSON accepted
run "test_custom_policy_valid_json" {
  command = plan

  variables {
    name          = "test-bucket"
    custom_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CustomStatement\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::test-bucket/*\"}]}"
  }

  assert {
    condition     = var.custom_policy != null
    error_message = "Valid JSON custom_policy should be accepted."
  }
}

# Test: invalid custom_policy JSON rejected
run "test_custom_policy_invalid_json" {
  command = plan

  variables {
    name          = "test-bucket"
    custom_policy = "not valid json {"
  }

  expect_failures = [
    var.custom_policy,
  ]
}

#-------------------------------------------------------------------------------
# Bucket Policy Resource Tests
#-------------------------------------------------------------------------------

# Test: no bucket policy created when no templates or custom policy
run "test_bucket_policy_not_created_by_default" {
  command = plan

  variables {
    name = "test-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 0
    error_message = "Bucket policy should not be created when no templates or custom policy specified."
  }
}

# Test: bucket policy created when policy_templates specified
run "test_bucket_policy_created_with_templates" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "Bucket policy should be created when policy_templates specified."
  }
}

# Test: bucket policy created when custom_policy specified
run "test_bucket_policy_created_with_custom_policy" {
  command = plan

  variables {
    name          = "test-bucket"
    custom_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CustomStatement\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::test-bucket/*\"}]}"
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "Bucket policy should be created when custom_policy specified."
  }
}

# Test: bucket policy references correct bucket
run "test_bucket_policy_bucket_reference" {
  command = plan

  variables {
    name             = "my-test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = aws_s3_bucket_policy.this[0].bucket == aws_s3_bucket.this.id
    error_message = "Bucket policy should reference the correct bucket."
  }
}

# Test: bucket policy has correct policy version
run "test_bucket_policy_version" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Version == "2012-10-17"
    error_message = "Bucket policy should have Version 2012-10-17."
  }
}

# Test: bucket policy contains template statements
run "test_bucket_policy_contains_template_statements" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 1
    error_message = "Bucket policy should contain 1 statement from template."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Sid == "DenyInsecureTransport"
    error_message = "Bucket policy should contain DenyInsecureTransport statement."
  }
}

# Test: bucket policy contains custom policy statements
run "test_bucket_policy_contains_custom_statements" {
  command = plan

  variables {
    name          = "test-bucket"
    custom_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CustomReadAccess\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::test-bucket/*\"}]}"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 1
    error_message = "Bucket policy should contain 1 statement from custom policy."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Sid == "CustomReadAccess"
    error_message = "Bucket policy should contain CustomReadAccess statement."
  }
}

# Test: bucket policy merges template and custom statements
run "test_bucket_policy_merges_template_and_custom" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport"]
    custom_policy    = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CustomReadAccess\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::test-bucket/*\"}]}"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 2
    error_message = "Bucket policy should contain 2 statements (1 template + 1 custom)."
  }
}

# Test: bucket policy with multiple templates
run "test_bucket_policy_multiple_templates" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport", "alb_access_logs"]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 4
    error_message = "Bucket policy should contain 4 statements (1 + 3 from templates)."
  }
}

# Test: bucket policy with all templates
run "test_bucket_policy_all_templates" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["deny_insecure_transport", "alb_access_logs", "nlb_access_logs", "vpc_flow_logs", "cloudfront_oac_read"]
    cloudfront_distribution_arns = [
      "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
    ]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 9
    error_message = "Bucket policy should contain 9 statements from all templates."
  }
}

# Test: bucket policy ALB access logs has correct resource ARN
run "test_bucket_policy_alb_logs_resource_arn" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["alb_access_logs"]
  }

  assert {
    condition     = can(regex("AWSLogs/123456789012/", jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Resource))
    error_message = "ALB logs policy should reference correct account ID in resource ARN."
  }
}

# Test: bucket policy VPC flow logs uses correct region
run "test_bucket_policy_vpc_flow_logs_region" {
  command = plan

  variables {
    name             = "test-bucket"
    policy_templates = ["vpc_flow_logs"]
  }

  assert {
    condition     = can(regex("us-east-1", jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Condition.ArnLike["aws:SourceArn"]))
    error_message = "VPC flow logs policy should use correct region."
  }
}

#-------------------------------------------------------------------------------
# Output Tests
#-------------------------------------------------------------------------------

# Test: bucket_id output is not null
run "test_output_bucket_id" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_id != null && output.bucket_id != ""
    error_message = "bucket_id output should not be null or empty."
  }
}

# Test: bucket_arn output is not null
run "test_output_bucket_arn" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_arn != null && output.bucket_arn != ""
    error_message = "bucket_arn output should not be null or empty."
  }
}

# Test: bucket_domain_name output is not null
run "test_output_bucket_domain_name" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_domain_name != null && output.bucket_domain_name != ""
    error_message = "bucket_domain_name output should not be null or empty."
  }
}

# Test: bucket_regional_domain_name output is not null
run "test_output_bucket_regional_domain_name" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_regional_domain_name != null && output.bucket_regional_domain_name != ""
    error_message = "bucket_regional_domain_name output should not be null or empty."
  }
}

# Test: bucket_hosted_zone_id output is not null
run "test_output_bucket_hosted_zone_id" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_hosted_zone_id != null
    error_message = "bucket_hosted_zone_id output should not be null."
  }
}

# Test: bucket_region output is not null
run "test_output_bucket_region" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_region != null
    error_message = "bucket_region output should not be null."
  }
}

# Test: bucket_policy output is null when no policy
run "test_output_bucket_policy_null_when_no_policy" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.bucket_policy == null
    error_message = "bucket_policy output should be null when no policy specified."
  }
}

# Test: bucket_policy output contains policy when templates specified
run "test_output_bucket_policy_with_templates" {
  command = plan

  variables {
    name             = "my-test-bucket"
    policy_templates = ["deny_insecure_transport"]
  }

  assert {
    condition     = output.bucket_policy != null
    error_message = "bucket_policy output should not be null when policy templates specified."
  }

  assert {
    condition     = can(jsondecode(output.bucket_policy))
    error_message = "bucket_policy output should be valid JSON."
  }
}

# Test: versioning_enabled output reflects variable
run "test_output_versioning_enabled_default" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.versioning_enabled == false
    error_message = "versioning_enabled output should be false by default."
  }
}

# Test: versioning_enabled output when enabled
run "test_output_versioning_enabled_true" {
  command = plan

  variables {
    name               = "my-test-bucket"
    versioning_enabled = true
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "versioning_enabled output should be true when enabled."
  }
}

# Test: encryption_algorithm output is AES256 by default
run "test_output_encryption_algorithm_default" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.encryption_algorithm == "AES256"
    error_message = "encryption_algorithm output should be AES256 by default."
  }
}

# Test: encryption_algorithm output is aws:kms when KMS key provided
run "test_output_encryption_algorithm_kms" {
  command = plan

  variables {
    name       = "my-test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = output.encryption_algorithm == "aws:kms"
    error_message = "encryption_algorithm output should be aws:kms when KMS key provided."
  }
}

# Test: kms_key_id output is null by default
run "test_output_kms_key_id_default" {
  command = plan

  variables {
    name = "my-test-bucket"
  }

  assert {
    condition     = output.kms_key_id == null
    error_message = "kms_key_id output should be null by default."
  }
}

# Test: kms_key_id output returns key when provided
run "test_output_kms_key_id_with_key" {
  command = plan

  variables {
    name       = "my-test-bucket"
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = output.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "kms_key_id output should return the provided key."
  }
}
