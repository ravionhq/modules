################################################################################
# Prometheus Workspace Module Tests
################################################################################

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
    }
  }
  mock_resource "aws_prometheus_workspace" {
    defaults = {
      arn                 = "arn:aws:aps:us-west-2:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
      prometheus_endpoint = "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/"
    }
  }
}

variables {
  name = "test-metrics"
}

run "creates_a_workspace_with_default_retention" {
  command = apply

  assert {
    condition     = aws_prometheus_workspace.this.alias == "test-metrics" && aws_prometheus_workspace.this.tags["Name"] == "test-metrics"
    error_message = "The workspace should be aliased and tagged with its name."
  }

  assert {
    condition     = aws_prometheus_workspace.this.kms_key_arn == null
    error_message = "The workspace should use an AWS owned key by default."
  }

  assert {
    condition     = aws_prometheus_workspace_configuration.this.retention_period_in_days == 150
    error_message = "The workspace should keep samples for 150 days by default."
  }

  assert {
    condition     = output.query_url == "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The query URL should be the workspace endpoint without its trailing slash."
  }

  assert {
    condition     = output.remote_write_url == "https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-1234abcd-12ab-34cd-56ef-1234567890ab/api/v1/remote_write"
    error_message = "The remote write URL should be the workspace endpoint's remote_write API."
  }

  assert {
    condition     = output.workspace_arn == "arn:aws:aps:us-west-2:123456789012:workspace/ws-1234abcd-12ab-34cd-56ef-1234567890ab" && output.region == "us-west-2"
    error_message = "The workspace ARN and region should be outputs."
  }
}

run "retention_and_kms_key_are_configurable" {
  command = plan

  variables {
    retention_period_in_days = 30
    kms_key_arn              = "arn:aws:kms:us-west-2:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = aws_prometheus_workspace_configuration.this.retention_period_in_days == 30
    error_message = "The workspace should keep samples for the configured number of days."
  }

  assert {
    condition     = aws_prometheus_workspace.this.kms_key_arn == "arn:aws:kms:us-west-2:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The workspace should be encrypted with the configured key."
  }
}

run "blank_kms_key_uses_an_aws_owned_key" {
  command = plan

  variables {
    kms_key_arn = " "
  }

  assert {
    condition     = aws_prometheus_workspace.this.kms_key_arn == null
    error_message = "A blank key ARN should leave the workspace on an AWS owned key."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "-bad name"
  }

  expect_failures = [var.name]
}

run "rejects_retention_beyond_three_years" {
  command = plan

  variables {
    retention_period_in_days = 1096
  }

  expect_failures = [var.retention_period_in_days]
}

run "rejects_fractional_retention" {
  command = plan

  variables {
    retention_period_in_days = 1.5
  }

  expect_failures = [var.retention_period_in_days]
}

run "rejects_invalid_kms_key_arn" {
  command = plan

  variables {
    kms_key_arn = "alias/my-key"
  }

  expect_failures = [var.kms_key_arn]
}
