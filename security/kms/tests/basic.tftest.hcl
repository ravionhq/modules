# KMS module tests — run from module root: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_kms_key.this
    values = {
      key_id = "00000000-0000-0000-0000-000000000000"
      arn    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = aws_kms_alias.this
    values = {
      arn = "arn:aws:kms:us-east-1:123456789012:alias/test"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      id         = "123456789012"
      user_id    = "AROATEST"
    }
  }
}

variables {
  name = "test-key"
}

################################################################################
# Defaults — symmetric envelope-encryption key
################################################################################

run "defaults_symmetric" {
  command = plan

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "Default key_spec should be SYMMETRIC_DEFAULT"
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT"
    error_message = "Default key_usage should be ENCRYPT_DECRYPT"
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Default deletion_window_in_days must be 30 (maximum safety window)"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Symmetric keys must enable rotation by default"
  }

  assert {
    condition     = aws_kms_key.this.multi_region == false
    error_message = "Default multi_region should be false"
  }
}

run "alias_defaults_to_name" {
  command = plan

  assert {
    condition     = aws_kms_alias.this.name == "alias/test-key"
    error_message = "Alias should default to alias/<name>"
  }

  assert {
    condition     = aws_kms_alias.this.target_key_id == aws_kms_key.this.key_id
    error_message = "Alias must target the KMS key created by this module"
  }
}

run "alias_override" {
  command = plan

  variables {
    alias = "custom-alias"
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/custom-alias"
    error_message = "Alias should respect var.alias when provided"
  }
}

################################################################################
# Asymmetric signing key (RSA_2048 + SIGN_VERIFY)
################################################################################

run "asymmetric_signing_key" {
  command = plan

  variables {
    key_spec  = "RSA_2048"
    key_usage = "SIGN_VERIFY"
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "RSA_2048"
    error_message = "Key spec should be RSA_2048"
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "SIGN_VERIFY"
    error_message = "Key usage should be SIGN_VERIFY"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == null
    error_message = "Asymmetric keys must NOT have enable_key_rotation set (AWS rejects rotation on asymmetric)"
  }
}

run "hmac_key" {
  command = plan

  variables {
    key_spec  = "HMAC_256"
    key_usage = "GENERATE_VERIFY_MAC"
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "HMAC_256"
    error_message = "Key spec should be HMAC_256"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == null
    error_message = "HMAC keys do not support automatic rotation"
  }
}

################################################################################
# Tagging
################################################################################

run "default_tags" {
  command = plan

  assert {
    condition     = aws_kms_key.this.tags["ManagedBy"] == "terraform"
    error_message = "Default ManagedBy tag must be present"
  }

  assert {
    condition     = aws_kms_key.this.tags["Module"] == "security/kms"
    error_message = "Default Module tag must be present"
  }
}

run "user_tags_merged" {
  command = plan

  variables {
    tags = {
      Environment = "prod"
      Owner       = "platform"
    }
  }

  assert {
    condition     = aws_kms_key.this.tags["Environment"] == "prod"
    error_message = "User tag 'Environment' must propagate"
  }

  assert {
    condition     = aws_kms_key.this.tags["Owner"] == "platform"
    error_message = "User tag 'Owner' must propagate"
  }

  assert {
    condition     = aws_kms_key.this.tags["ManagedBy"] == "terraform"
    error_message = "Default tags must remain alongside user tags"
  }
}

################################################################################
# Key policy: root statement is always present
################################################################################

run "root_iam_statement_present" {
  command = plan

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "EnableIAMUserPermissions",
    )
    error_message = "Key policy must grant root AWS IAM permissions (EnableIAMUserPermissions)"
  }

  assert {
    condition = [for s in jsondecode(aws_kms_key.this.policy).Statement :
    s if s.Sid == "EnableIAMUserPermissions"][0].Principal.AWS == "arn:aws:iam::123456789012:root"
    error_message = "Root statement must use the account root ARN"
  }
}

################################################################################
# Key policy: optional statements absent by default
################################################################################

run "no_optional_statements_by_default" {
  command = plan

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowKeyAdministration",
    )
    error_message = "AllowKeyAdministration must be absent when key_administrator_role_arns is empty"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowKeyUse",
    )
    error_message = "AllowKeyUse must be absent when key_user_role_arns is empty"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowSign",
    )
    error_message = "AllowSign must be absent when signer_role_arns is empty"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowPublicKeyRead",
    )
    error_message = "AllowPublicKeyRead must be absent when public_key_reader_role_arns is empty"
  }
}

################################################################################
# Admin statement: grants admin actions, never grants Sign/Encrypt/Decrypt
################################################################################

run "admin_statement_when_configured" {
  command = plan

  variables {
    key_administrator_role_arns = ["arn:aws:iam::123456789012:role/kms-admin"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowKeyAdministration",
    )
    error_message = "AllowKeyAdministration must be present when key_administrator_role_arns is non-empty"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyAdministration"][0].Action,
      "kms:Sign",
    )
    error_message = "Administrators must NOT receive kms:Sign"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyAdministration"][0].Action,
      "kms:Encrypt",
    )
    error_message = "Administrators must NOT receive kms:Encrypt"
  }
}

################################################################################
# User statement: actions match key_usage
################################################################################

run "user_statement_encrypt_decrypt_actions" {
  command = plan

  variables {
    key_user_role_arns = ["arn:aws:iam::123456789012:role/app"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyUse"][0].Action,
      "kms:Decrypt",
    )
    error_message = "AllowKeyUse for ENCRYPT_DECRYPT must grant kms:Decrypt"
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyUse"][0].Action,
      "kms:GenerateDataKey",
    )
    error_message = "AllowKeyUse for ENCRYPT_DECRYPT must grant kms:GenerateDataKey"
  }
}

run "user_statement_sign_verify_actions" {
  command = plan

  variables {
    key_spec           = "RSA_2048"
    key_usage          = "SIGN_VERIFY"
    key_user_role_arns = ["arn:aws:iam::123456789012:role/verifier"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyUse"][0].Action,
      "kms:Verify",
    )
    error_message = "AllowKeyUse for SIGN_VERIFY must grant kms:Verify"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowKeyUse"][0].Action,
      "kms:Sign",
    )
    error_message = "AllowKeyUse must NOT grant kms:Sign — that lives in AllowSign"
  }
}

################################################################################
# Signer statement: only renders when key_usage supports signing
################################################################################

run "signer_statement_sign_verify" {
  command = plan

  variables {
    key_spec         = "RSA_2048"
    key_usage        = "SIGN_VERIFY"
    signer_role_arns = ["arn:aws:iam::123456789012:role/signer"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowSign",
    )
    error_message = "AllowSign must be present for SIGN_VERIFY when signer_role_arns is non-empty"
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowSign"][0].Action,
      "kms:Sign",
    )
    error_message = "AllowSign for SIGN_VERIFY must grant kms:Sign"
  }
}

run "signer_statement_hmac" {
  command = plan

  variables {
    key_spec         = "HMAC_256"
    key_usage        = "GENERATE_VERIFY_MAC"
    signer_role_arns = ["arn:aws:iam::123456789012:role/mac-signer"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowSign"][0].Action,
      "kms:GenerateMac",
    )
    error_message = "AllowSign for GENERATE_VERIFY_MAC must grant kms:GenerateMac"
  }
}

run "signer_statement_omitted_for_encrypt_decrypt" {
  command = plan

  variables {
    signer_role_arns = ["arn:aws:iam::123456789012:role/wrong-target"]
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowSign",
    )
    error_message = "AllowSign must NOT render for ENCRYPT_DECRYPT keys (no signing semantics)"
  }
}

################################################################################
# Public key reader statement: grants GetPublicKey but NOT Sign or Verify
################################################################################

run "public_key_reader_does_not_get_sign" {
  command = plan

  variables {
    key_spec                    = "RSA_2048"
    key_usage                   = "SIGN_VERIFY"
    public_key_reader_role_arns = ["arn:aws:iam::123456789012:role/jwks-publisher"]
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Sid],
      "AllowPublicKeyRead",
    )
    error_message = "Policy must include an AllowPublicKeyRead statement"
  }

  assert {
    condition = contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowPublicKeyRead"][0].Action,
      "kms:GetPublicKey",
    )
    error_message = "AllowPublicKeyRead must grant kms:GetPublicKey"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowPublicKeyRead"][0].Action,
      "kms:Sign",
    )
    error_message = "AllowPublicKeyRead must NOT grant kms:Sign — readers must be cryptographically unable to forge signatures"
  }

  assert {
    condition = !contains(
      [for s in jsondecode(aws_kms_key.this.policy).Statement :
      s if s.Sid == "AllowPublicKeyRead"][0].Action,
      "kms:Verify",
    )
    error_message = "AllowPublicKeyRead must NOT grant kms:Verify"
  }
}

################################################################################
# Validation failures
################################################################################

run "invalid_key_spec_rejected" {
  command = plan

  variables {
    key_spec = "RSA_1024"
  }

  expect_failures = [
    var.key_spec,
  ]
}

run "invalid_key_usage_rejected" {
  command = plan

  variables {
    key_usage = "WRAP_UNWRAP"
  }

  expect_failures = [
    var.key_usage,
  ]
}

run "deletion_window_below_min_rejected" {
  command = plan

  variables {
    deletion_window_in_days = 6
  }

  expect_failures = [
    var.deletion_window_in_days,
  ]
}

run "deletion_window_above_max_rejected" {
  command = plan

  variables {
    deletion_window_in_days = 31
  }

  expect_failures = [
    var.deletion_window_in_days,
  ]
}

run "non_iam_arn_signer_rejected" {
  command = plan

  variables {
    signer_role_arns = ["not-an-arn"]
  }

  expect_failures = [
    var.signer_role_arns,
  ]
}

run "incomplete_iam_principal_arns_rejected" {
  command = plan

  variables {
    key_administrator_role_arns = ["arn:aws:iam::"]
    key_user_role_arns          = ["arn:aws:iam::123456789012:"]
    signer_role_arns            = ["arn:aws:iam::123456789012:role/"]
    public_key_reader_role_arns = ["arn:aws:iam::12345678901:root"]
  }

  expect_failures = [
    var.key_administrator_role_arns,
    var.key_user_role_arns,
    var.signer_role_arns,
    var.public_key_reader_role_arns,
  ]
}

run "valid_iam_principal_arns_accepted" {
  command = plan

  variables {
    key_administrator_role_arns = ["arn:aws:iam::123456789012:root"]
    key_user_role_arns          = ["arn:aws:iam::123456789012:role/application/data-reader"]
    signer_role_arns            = ["arn:aws-us-gov:iam::123456789012:role/signer"]
    public_key_reader_role_arns = ["arn:aws-cn:iam::123456789012:user/public-key-reader"]
  }
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "this-name-exceeds-the-sixty-four-character-limit-imposed-by-the-module-validation"
  }

  expect_failures = [
    var.name,
  ]
}
