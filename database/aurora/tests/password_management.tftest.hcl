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
    condition     = aws_rds_cluster.this.master_password_wo_version == 1 && aws_secretsmanager_secret_version.master_user[0].secret_string_wo_version == 1
    error_message = "The cluster and the secret should be written at the same password version."
  }

  assert {
    condition     = output.cluster_master_user_secret_arn == "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/temporal/db-AbCdEf"
    error_message = "cluster_master_user_secret_arn should return the named secret's ARN."
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
