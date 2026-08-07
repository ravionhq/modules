################################################################################
# RDS Proxy Module Unit Tests
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

  override_resource {
    target = aws_iam_role.this
    values = {
      arn = "arn:aws:iam::123456789012:role/test-proxy-rds-proxy"
    }
  }

  override_resource {
    target = aws_db_proxy_default_target_group.this
    values = {
      name = "default"
    }
  }
}

# Defaults shared by all runs; individual runs override as needed.
variables {
  name          = "test-proxy"
  engine_family = "POSTGRESQL"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-11111111", "subnet-22222222"]
  auth = [
    { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test-abc123" }
  ]
  db_instance_identifier = "test-db"
}

#-------------------------------------------------------------------------------
# Basic Plan & Defaults
#-------------------------------------------------------------------------------

run "test_basic_plan" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.name == "test-proxy"
    error_message = "Proxy should use var.name as its name."
  }

  assert {
    condition     = aws_db_proxy.this.require_tls == true
    error_message = "TLS should be required by default."
  }

  assert {
    condition     = aws_db_proxy.this.engine_family == "POSTGRESQL"
    error_message = "Engine family should be passed through."
  }

  assert {
    condition     = local.port == 5432
    error_message = "POSTGRESQL should default to port 5432."
  }

  assert {
    condition     = local.tags["Module"] == "database/rds-proxy"
    error_message = "Module default tag should be set."
  }
}

run "test_mysql_port_default" {
  command = plan

  variables {
    engine_family = "MYSQL"
  }

  assert {
    condition     = local.port == 3306
    error_message = "MYSQL should default to port 3306."
  }
}

run "test_sqlserver_port_default" {
  command = plan

  variables {
    engine_family = "SQLSERVER"
  }

  assert {
    condition     = local.port == 1433
    error_message = "SQLSERVER should default to port 1433."
  }
}

run "test_custom_port_override" {
  command = plan

  variables {
    port = 6543
  }

  assert {
    condition     = local.port == 6543
    error_message = "Custom port should override the engine family default."
  }
}

#-------------------------------------------------------------------------------
# Validation Tests
#-------------------------------------------------------------------------------

run "test_invalid_engine_family" {
  command = plan

  variables {
    engine_family = "ORACLE"
  }

  expect_failures = [
    var.engine_family,
  ]
}

run "test_auth_empty" {
  command = plan

  variables {
    auth = []
  }

  expect_failures = [
    var.auth,
  ]
}

run "test_auth_invalid_secret_arn" {
  command = plan

  variables {
    auth = [{ secret_arn = "not-an-arn" }]
  }

  expect_failures = [
    var.auth,
  ]
}

run "test_max_idle_above_max_connections" {
  command = plan

  variables {
    max_connections_percent      = 50
    max_idle_connections_percent = 80
  }

  expect_failures = [
    var.max_idle_connections_percent,
  ]
}

#-------------------------------------------------------------------------------
# Target Exclusivity Tests
#-------------------------------------------------------------------------------

run "test_both_targets_rejected" {
  command = plan

  variables {
    db_cluster_identifier = "test-cluster"
  }

  expect_failures = [
    aws_db_proxy_target.this,
  ]
}

run "test_no_target_rejected" {
  command = plan

  variables {
    db_instance_identifier = null
  }

  expect_failures = [
    aws_db_proxy_target.this,
  ]
}

#-------------------------------------------------------------------------------
# Security Group & IAM Role Preconditions
#-------------------------------------------------------------------------------

run "test_sg_disabled_requires_id" {
  command = plan

  variables {
    security_group_creation_enabled = false
  }

  expect_failures = [
    aws_db_proxy.this,
  ]
}

run "test_sg_disabled_with_id" {
  command = plan

  variables {
    security_group_creation_enabled = false
    security_group_id               = "sg-12345678"
  }

  assert {
    condition     = local.security_group_id == "sg-12345678"
    error_message = "Provided security group ID should be used."
  }
}

run "test_iam_role_disabled_requires_arn" {
  command = plan

  variables {
    iam_role_creation_enabled = false
  }

  expect_failures = [
    aws_db_proxy.this,
  ]
}

run "test_iam_role_disabled_with_arn" {
  command = plan

  variables {
    iam_role_creation_enabled = false
    iam_role_arn              = "arn:aws:iam::123456789012:role/custom-proxy-role"
  }

  assert {
    condition     = local.iam_role_arn == "arn:aws:iam::123456789012:role/custom-proxy-role"
    error_message = "Provided IAM role ARN should be used."
  }
}
