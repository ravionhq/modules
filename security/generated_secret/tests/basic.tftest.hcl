# Generated secret module tests — run from module root: tofu test

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      id         = "123456789012"
      user_id    = "AROATEST"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }
}

mock_provider "random" {}

variables {
  name = "ravion/app/production/master-key"
}

################################################################################
# Parameter Store (default)
################################################################################

run "parameter_store_default" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.this) == 1 && length(aws_secretsmanager_secret.this) == 0
    error_message = "Parameter Store must be the default store"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].name == "/ravion/app/production/master-key"
    error_message = "Parameter names must start with a slash"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].type == "SecureString"
    error_message = "The parameter must be a SecureString"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].value_wo_version == 1
    error_message = "The first value version must be 1"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].tags["Module"] == "security/generated_secret"
    error_message = "Default tags must be present"
  }
}

run "parameter_store_rotation" {
  command = plan

  variables {
    rotation_version = 2
  }

  assert {
    condition     = aws_ssm_parameter.this[0].value_wo_version == 2
    error_message = "rotation_version must drive the write-only value version"
  }
}

################################################################################
# Secrets Manager
################################################################################

run "secrets_manager" {
  command = plan

  variables {
    name  = "/ravion/app/production/master-key"
    store = "secrets_manager"
    tags  = { Owner = "platform" }
  }

  assert {
    condition     = length(aws_ssm_parameter.this) == 0 && length(aws_secretsmanager_secret.this) == 1 && length(aws_secretsmanager_secret_version.this) == 1
    error_message = "Secrets Manager store must create only the secret and its version"
  }

  assert {
    condition     = aws_secretsmanager_secret.this[0].name == "ravion/app/production/master-key"
    error_message = "Secret names must not start with a slash"
  }

  assert {
    condition     = aws_secretsmanager_secret.this[0].recovery_window_in_days == 30
    error_message = "Default recovery window must be 30 days"
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string_wo_version == 1
    error_message = "The first value version must be 1"
  }

  assert {
    condition     = aws_secretsmanager_secret.this[0].tags["Owner"] == "platform" && aws_secretsmanager_secret.this[0].tags["ManagedBy"] == "terraform"
    error_message = "User tags must merge with default tags"
  }
}

################################################################################
# Validation
################################################################################

run "rejects_short_length" {
  command = plan

  variables {
    length = 8
  }

  expect_failures = [var.length]
}

run "rejects_unknown_store" {
  command = plan

  variables {
    store = "vault"
  }

  expect_failures = [var.store]
}

run "rejects_reserved_parameter_prefix" {
  command = plan

  variables {
    name = "aws/prod/key"
  }

  expect_failures = [var.name]
}

run "allows_secrets_manager_characters" {
  command = plan

  variables {
    name  = "app/prod+key=1@x"
    store = "secrets_manager"
  }

  assert {
    condition     = aws_secretsmanager_secret.this[0].name == "app/prod+key=1@x"
    error_message = "Secrets Manager names may contain + = @"
  }
}

run "rejects_secrets_manager_characters_in_parameter_store" {
  command = plan

  variables {
    name = "app/prod+key"
  }

  expect_failures = [var.name]
}
