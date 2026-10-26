mock_provider "aws" {}

variables {
  name   = "test-repository"
  region = "us-east-1"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "MUTABLE"
    error_message = "Image tags should be mutable by default."
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Image scanning on push should be enabled by default."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "Repository encryption should default to AES256."
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "No lifecycle policy should be created when the default policy is disabled."
  }

  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "No repository policy should be created when no principals are configured."
  }
}

run "default_lifecycle_policy" {
  command = plan

  variables {
    default_lifecycle_policy_enabled = true
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.tagStatus == "untagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 14
    )
    error_message = "The default policy should expire untagged images after 14 days."
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.tagStatus == "any" &&
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.countNumber == 100
    )
    error_message = "The default policy should keep the newest 100 images, tagged or untagged."
  }
}

run "custom_lifecycle_counts" {
  command = plan

  variables {
    default_lifecycle_policy_enabled = true
    untagged_image_expiry_days       = 7
    max_tagged_image_count           = 25
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 7 &&
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.countNumber == 25
    )
    error_message = "The lifecycle policy should use the configured image counts."
  }
}

run "generated_repository_policy" {
  command = plan

  variables {
    allowed_pull_principal_arns = ["arn:aws:iam::123456789012:role/pull"]
    allowed_push_principal_arns = ["arn:aws:iam::123456789012:role/push"]
  }

  assert {
    condition = contains(
      [for statement in jsondecode(aws_ecr_repository_policy.this[0].policy).Statement : statement.Sid],
      "AllowPull",
    )
    error_message = "A configured pull principal should create an AllowPull statement."
  }

  assert {
    condition = contains(
      [for statement in jsondecode(aws_ecr_repository_policy.this[0].policy).Statement : statement.Sid],
      "AllowPush",
    )
    error_message = "A configured push principal should create an AllowPush statement."
  }
}

run "kms_key" {
  command = plan

  variables {
    encryption_type = "KMS"
    kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "The configured KMS key ARN should be assigned to the repository."
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "Invalid_name"
  }

  expect_failures = [var.name]
}
