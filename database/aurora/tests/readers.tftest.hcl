################################################################################
# Aurora Reader Tests
#
# Covers generated reader instances: their class, their failover tiers, and
# Serverless v2 readers behind a provisioned writer (a mixed-configuration
# cluster), which needs the cluster's scaling configuration while the writer
# keeps its instance class.
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

variables {
  name                               = "test-db"
  region                             = "us-east-1"
  vpc_id                             = "vpc-12345678"
  subnet_ids                         = ["subnet-11111111", "subnet-22222222"]
  security_group_creation_enabled    = false
  security_group_id                  = "sg-12345678"
  monitoring_interval                = 0
  cloudwatch_alarms_creation_enabled = false
  engine                             = "aurora-postgresql"
  engine_version                     = "17"
  instance_class                     = "db.r8g.2xlarge"
  master_username                    = "dbadmin"
  reader_count                       = 1
}

run "provisioned_readers_by_default" {
  command = plan

  assert {
    condition     = aws_rds_cluster_instance.this["writer"].instance_class == "db.r8g.2xlarge" && aws_rds_cluster_instance.this["reader-1"].instance_class == "db.r8g.2xlarge"
    error_message = "Readers must default to the writer's instance class."
  }

  assert {
    condition     = aws_rds_cluster_instance.this["writer"].promotion_tier == 0 && aws_rds_cluster_instance.this["reader-1"].promotion_tier == 1
    error_message = "The writer must keep tier 0 and the first reader tier 1."
  }

  assert {
    condition     = length(aws_rds_cluster.this.serverlessv2_scaling_configuration) == 0
    error_message = "A provisioned cluster without Serverless v2 readers must not set a scaling configuration."
  }
}

run "serverless_readers_behind_provisioned_writer" {
  command = plan

  variables {
    reader_count                 = 2
    reader_serverless_v2_scaling = { min_capacity = 2, max_capacity = 32 }
    reader_promotion_tier        = 2
  }

  assert {
    condition     = aws_rds_cluster_instance.this["writer"].instance_class == "db.r8g.2xlarge"
    error_message = "The writer must keep instance_class."
  }

  assert {
    condition     = aws_rds_cluster_instance.this["reader-1"].instance_class == "db.serverless" && aws_rds_cluster_instance.this["reader-2"].instance_class == "db.serverless"
    error_message = "Readers must use db.serverless."
  }

  assert {
    condition     = aws_rds_cluster.this.serverlessv2_scaling_configuration[0].min_capacity == 2 && aws_rds_cluster.this.serverlessv2_scaling_configuration[0].max_capacity == 32
    error_message = "The cluster must carry the readers' Serverless v2 capacity range."
  }

  assert {
    condition     = aws_rds_cluster_instance.this["reader-1"].promotion_tier == 2 && aws_rds_cluster_instance.this["reader-2"].promotion_tier == 3
    error_message = "Readers must take consecutive tiers from reader_promotion_tier."
  }
}

run "serverless_cluster_unchanged" {
  command = plan

  variables {
    instance_class        = "db.serverless"
    serverless_v2_scaling = { min_capacity = 0.5, max_capacity = 4 }
  }

  assert {
    condition     = aws_rds_cluster_instance.this["writer"].instance_class == "db.serverless" && aws_rds_cluster_instance.this["reader-1"].instance_class == "db.serverless"
    error_message = "A Serverless v2 cluster must use db.serverless for every instance."
  }

  assert {
    condition     = aws_rds_cluster.this.serverlessv2_scaling_configuration[0].max_capacity == 4
    error_message = "A Serverless v2 cluster must keep its own scaling configuration."
  }
}

run "reject_both_scaling_configurations" {
  command = plan

  variables {
    serverless_v2_scaling        = { min_capacity = 0.5, max_capacity = 4 }
    reader_serverless_v2_scaling = { min_capacity = 2, max_capacity = 32 }
  }

  expect_failures = [var.reader_serverless_v2_scaling]
}

run "reject_reader_class_with_serverless_readers" {
  command = plan

  variables {
    reader_instance_class        = "db.r8g.large"
    reader_serverless_v2_scaling = { min_capacity = 2, max_capacity = 32 }
  }

  expect_failures = [var.reader_serverless_v2_scaling]
}

run "reject_inverted_reader_capacity" {
  command = plan

  variables {
    reader_serverless_v2_scaling = { min_capacity = 8, max_capacity = 4 }
  }

  expect_failures = [var.reader_serverless_v2_scaling]
}

run "reject_reader_tier_past_15" {
  command = plan

  variables {
    reader_count          = 3
    reader_promotion_tier = 14
  }

  expect_failures = [var.reader_promotion_tier]
}
