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
    target = data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

run "test_password_management_and_preservation_conflict" {
  command = plan

  variables {
    name                                      = "test-cluster"
    engine                                    = "aurora-postgresql"
    engine_version                            = "16.4"
    instance_class                            = "db.t4g.medium"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled           = false
    security_group_id                         = "sg-12345678"
    master_username                           = "dbadmin"
    master_user_password_management_enabled   = true
    master_user_password_preservation_enabled = true
  }

  expect_failures = [
    var.master_user_password_preservation_enabled,
  ]
}

run "test_fresh_cluster_requires_master_credentials" {
  command = plan

  variables {
    name                                      = "test-cluster"
    engine                                    = "aurora-postgresql"
    engine_version                            = "16.4"
    instance_class                            = "db.t4g.medium"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled           = false
    security_group_id                         = "sg-12345678"
    master_username                           = "dbadmin"
    master_user_password_management_enabled   = false
    master_user_password_preservation_enabled = true
  }

  override_data {
    target = data.aws_rds_cluster.password_preservation
    values = {
      arn = ""
    }
  }

  expect_failures = [
    aws_rds_cluster.this,
  ]
}

run "test_unmanaged_import_password_is_omitted" {
  command = plan

  variables {
    name                                      = "test-cluster"
    engine                                    = "aurora-postgresql"
    engine_version                            = "16.4"
    instance_class                            = "db.t4g.medium"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled           = false
    security_group_id                         = "sg-12345678"
    master_username                           = "dbadmin"
    master_user_password_management_enabled   = false
    master_user_password_preservation_enabled = true
  }

  override_data {
    target = data.aws_rds_cluster.password_preservation
    values = {
      arn = "arn:aws:rds:us-east-1:123456789012:cluster:test-cluster"
    }
  }

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == null
    error_message = "manage_master_user_password should be omitted when password management is disabled."
  }

  assert {
    condition     = data.aws_rds_cluster.password_preservation[0].arn == "arn:aws:rds:us-east-1:123456789012:cluster:test-cluster"
    error_message = "Password preservation should verify that the imported cluster exists."
  }
}

run "test_named_secret_holds_module_managed_password" {
  command = apply

  variables {
    name                                    = "test-cluster"
    engine                                  = "aurora-postgresql"
    engine_version                          = "16.4"
    instance_class                          = "db.t4g.medium"
    vpc_id                                  = "vpc-12345678"
    subnet_ids                              = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled         = false
    security_group_id                       = "sg-12345678"
    master_username                         = "dbadmin"
    master_user_password_management_enabled = false
    master_user_secret_name                 = "prod/temporal/db"
    master_user_secret_kms_key_id           = "arn:aws:kms:us-east-1:123456789012:key/test"
  }

  override_resource {
    target = aws_secretsmanager_secret.master_user
    values = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/temporal/db-AbCdEf"
    }
  }

  override_resource {
    target = aws_secretsmanager_secret_version.master_user
    values = {
      version_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  # tofu test cannot mock the ephemeral secret read, so its module is
  # overridden with what it would return.
  override_module {
    target = module.master_user_secret_password
    outputs = {
      password = "test-password"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.master_user[0].name == "prod/temporal/db"
    error_message = "The named secret should be created with master_user_secret_name."
  }

  assert {
    condition     = aws_secretsmanager_secret.master_user[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/test"
    error_message = "The named secret should use master_user_secret_kms_key_id."
  }

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == null
    error_message = "AWS password management should be off when the module owns the secret."
  }

  assert {
    condition     = aws_rds_cluster.this.master_password == null
    error_message = "The plain master_password argument must stay unset so the password never reaches state."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.master_user[0].secret_string_wo_version == 1
    error_message = "The secret should be written at master_user_secret_version."
  }

  assert {
    condition     = aws_rds_cluster.this.master_password_wo_version == parseint(substr(sha256("11111111-1111-1111-1111-111111111111"), 0, 12), 16)
    error_message = "The cluster's password version should follow the secret's version ID, so the cluster is rewritten from the secret whenever the secret changes."
  }

  assert {
    condition     = output.cluster_master_user_secret_arn == "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/temporal/db-AbCdEf"
    error_message = "cluster_master_user_secret_arn should return the named secret's ARN."
  }
}

# Renaming the secret recreates it with a new password. The cluster must take
# that password too even though master_user_secret_version did not change: its
# password version follows the new secret version's ID.
run "test_renamed_secret_rewrites_cluster_password" {
  command = apply

  variables {
    name                                    = "test-cluster"
    engine                                  = "aurora-postgresql"
    engine_version                          = "16.4"
    instance_class                          = "db.t4g.medium"
    vpc_id                                  = "vpc-12345678"
    subnet_ids                              = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled         = false
    security_group_id                       = "sg-12345678"
    master_username                         = "dbadmin"
    master_user_password_management_enabled = false
    master_user_secret_name                 = "prod/temporal/db-renamed"
    master_user_secret_kms_key_id           = "arn:aws:kms:us-east-1:123456789012:key/test"
  }

  override_resource {
    target = aws_secretsmanager_secret_version.master_user
    values = {
      version_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  override_module {
    target = module.master_user_secret_password
    outputs = {
      password = "test-password-renamed"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.master_user[0].name == "prod/temporal/db-renamed"
    error_message = "The secret should be recreated under its new name."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.master_user[0].secret_string_wo_version == 1
    error_message = "The rename should not need master_user_secret_version to change."
  }

  assert {
    condition     = aws_rds_cluster.this.master_password_wo_version == parseint(substr(sha256("22222222-2222-2222-2222-222222222222"), 0, 12), 16)
    error_message = "A renamed secret should rewrite the cluster's password from the new secret."
  }

  assert {
    condition     = aws_rds_cluster.this.master_password_wo_version != parseint(substr(sha256("11111111-1111-1111-1111-111111111111"), 0, 12), 16)
    error_message = "The cluster's password version should change when the secret is replaced."
  }
}

run "test_named_secret_requires_password_management_off" {
  command = plan

  variables {
    name                            = "test-cluster"
    engine                          = "aurora-postgresql"
    engine_version                  = "16.4"
    instance_class                  = "db.t4g.medium"
    vpc_id                          = "vpc-12345678"
    subnet_ids                      = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled = false
    security_group_id               = "sg-12345678"
    master_username                 = "dbadmin"
    master_user_secret_name         = "prod/temporal/db"
  }

  expect_failures = [
    var.master_user_secret_name,
  ]
}

run "test_named_secret_conflicts_with_master_password" {
  command = plan

  variables {
    name                                    = "test-cluster"
    engine                                  = "aurora-postgresql"
    engine_version                          = "16.4"
    instance_class                          = "db.t4g.medium"
    vpc_id                                  = "vpc-12345678"
    subnet_ids                              = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled         = false
    security_group_id                       = "sg-12345678"
    master_username                         = "dbadmin"
    master_user_password_management_enabled = false
    master_user_secret_name                 = "prod/temporal/db"
    master_password                         = "supersecretpassword"
  }

  expect_failures = [
    var.master_user_secret_name,
  ]
}

run "test_named_secret_conflicts_with_preservation" {
  command = plan

  variables {
    name                                      = "test-cluster"
    engine                                    = "aurora-postgresql"
    engine_version                            = "16.4"
    instance_class                            = "db.t4g.medium"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled           = false
    security_group_id                         = "sg-12345678"
    master_username                           = "dbadmin"
    master_user_password_management_enabled   = false
    master_user_password_preservation_enabled = true
    master_user_secret_name                   = "prod/temporal/db"
  }

  override_data {
    target = data.aws_rds_cluster.password_preservation
    values = {
      arn = "arn:aws:rds:us-east-1:123456789012:cluster:test-cluster"
    }
  }

  expect_failures = [
    var.master_user_secret_name,
  ]
}
