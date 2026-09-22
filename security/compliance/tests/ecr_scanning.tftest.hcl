mock_provider "aws" {
  override_data {
    target = data.aws_regions.enabled
    values = {
      names = ["us-east-1", "us-west-2"]
    }
  }
}

variables {
  regions = ["us-west-2", "us-east-1"]
}

run "all_repositories_scan_on_push_in_each_region" {
  command = plan

  assert {
    condition     = toset(keys(aws_ecr_registry_scanning_configuration.this)) == toset(var.regions)
    error_message = "Each selected Region must have exactly one registry scanning configuration."
  }

  assert {
    condition = alltrue([
      for region, configuration in aws_ecr_registry_scanning_configuration.this :
      configuration.region == region && configuration.scan_type == "BASIC" &&
      length(configuration.rule) == 1 &&
      one(configuration.rule).scan_frequency == "SCAN_ON_PUSH" &&
      length(one(configuration.rule).repository_filter) == 1 &&
      one(one(configuration.rule).repository_filter).filter == "*" &&
      one(one(configuration.rule).repository_filter).filter_type == "WILDCARD"
    ])
    error_message = "Basic scan-on-push must cover all existing and future repositories in every selected Region."
  }

  assert {
    condition = toset(keys(aws_guardduty_detector.this)) == toset(keys(aws_ecr_registry_scanning_configuration.this)) && alltrue([
      for region, detector in aws_guardduty_detector.this : detector.region == region && detector.enable
    ])
    error_message = "GuardDuty and ECR scanning must cover the same selected Regions."
  }

  assert {
    condition     = output.regions == tolist(["us-east-1", "us-west-2"])
    error_message = "Regions must be output in a stable order."
  }
}

run "single_region" {
  command = plan

  variables {
    regions = ["us-east-1"]
  }

  assert {
    condition     = length(aws_ecr_registry_scanning_configuration.this) == 1 && length(aws_guardduty_detector.this) == 1 && output.regions == tolist(["us-east-1"])
    error_message = "Only the selected Region may be managed."
  }
}

run "rejects_region_not_enabled_for_account" {
  command = plan

  variables {
    regions = ["eu-west-1"]
  }

  expect_failures = [
    aws_ecr_registry_scanning_configuration.this["eu-west-1"],
    aws_guardduty_detector.this["eu-west-1"],
  ]
}

run "rejects_empty_regions" {
  command = plan

  variables {
    regions = []
  }

  expect_failures = [var.regions]
}

run "rejects_duplicate_regions" {
  command = plan

  variables {
    regions = ["us-east-1", "us-east-1"]
  }

  expect_failures = [var.regions]
}

run "rejects_invalid_region_code" {
  command = plan

  variables {
    regions = ["not-a-region"]
  }

  expect_failures = [var.regions]
}
