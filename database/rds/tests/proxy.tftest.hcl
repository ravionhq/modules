################################################################################
# RDS Proxy Integration Tests
#
# Covers the optional RDS Proxy wiring: engine family mapping, auth secret
# resolution, preconditions, and that the combined plan graph (database
# security group ingress from the proxy security group, proxy targeting the
# database) resolves without dependency cycles.
################################################################################

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
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }

  override_data {
    target = module.proxy.data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }

  # The proxy security group ID feeds the database security group's ingress
  # rule validation, which requires an sg- prefix.
  override_resource {
    target = module.proxy.module.security_group.aws_security_group.this
    values = {
      id = "sg-proxy123456"
    }
  }

  override_resource {
    target = module.proxy.aws_iam_role.this
    values = {
      arn = "arn:aws:iam::123456789012:role/test-db-rds-proxy"
    }
  }

  override_resource {
    target = module.proxy.aws_db_proxy_default_target_group.this
    values = {
      name = "default"
    }
  }

  # The mock provider materializes computed lists as empty; provide the managed
  # master user secret the proxy auth defaults to.
  override_resource {
    target = aws_db_instance.this
    values = {
      master_user_secret = [{
        kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test-master-abc123"
        secret_status = "active"
      }]
    }
  }
}

variables {
  name              = "test-db"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  vpc_id            = "vpc-12345678"
  subnet_ids        = ["subnet-11111111", "subnet-22222222"]
  username          = "admin"
}

run "test_proxy_not_created_by_default" {
  command = plan

  assert {
    condition     = local.create_proxy == false
    error_message = "Proxy should not be created by default."
  }
}

# Full plan with the proxy enabled. This exercises the complete dependency
# graph: DB security group ingress references the proxy security group while
# the proxy targets the database.
run "test_proxy_created_when_enabled" {
  command = plan

  variables {
    proxy_creation_enabled = true
  }

  assert {
    condition     = local.create_proxy == true
    error_message = "Proxy should be created when proxy_creation_enabled is true."
  }

  assert {
    condition     = local.proxy_engine_family == "POSTGRESQL"
    error_message = "postgres should map to the POSTGRESQL engine family."
  }
}

run "test_proxy_engine_family_mariadb" {
  command = plan

  variables {
    engine                 = "mariadb"
    proxy_creation_enabled = true
  }

  assert {
    condition     = local.proxy_engine_family == "MYSQL"
    error_message = "mariadb should map to the MYSQL engine family."
  }
}

run "test_proxy_engine_family_sqlserver" {
  command = plan

  variables {
    engine                 = "sqlserver-se"
    license_model          = "license-included"
    proxy_creation_enabled = true
  }

  assert {
    condition     = local.proxy_engine_family == "SQLSERVER"
    error_message = "sqlserver-se should map to the SQLSERVER engine family."
  }
}

run "test_proxy_rejected_for_oracle" {
  command = plan

  variables {
    engine                 = "oracle-ee"
    license_model          = "bring-your-own-license"
    proxy_creation_enabled = true
  }

  expect_failures = [
    aws_db_instance.this,
  ]
}

run "test_proxy_requires_secret_when_password_management_disabled" {
  command = plan

  variables {
    proxy_creation_enabled                  = true
    master_user_password_management_enabled = false
    password                                = "dummy-password-123"
  }

  expect_failures = [
    aws_db_instance.this,
  ]
}

run "test_proxy_explicit_auth_secrets" {
  command = plan

  variables {
    proxy_creation_enabled                  = true
    master_user_password_management_enabled = false
    password                                = "dummy-password-123"
    proxy_auth_secret_arns                  = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:custom-abc123"]
  }

  assert {
    condition     = local.proxy_auth_secret_arns[0] == "arn:aws:secretsmanager:us-east-1:123456789012:secret:custom-abc123"
    error_message = "Explicit proxy auth secrets should be used."
  }
}

run "test_proxy_master_secret_kms_key_passthrough" {
  command = plan

  variables {
    proxy_creation_enabled        = true
    master_user_secret_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = contains(local.proxy_secret_kms_key_arns, "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012")
    error_message = "Master user secret KMS key ARN should be passed to the proxy."
  }
}
