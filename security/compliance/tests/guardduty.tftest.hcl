# GuardDuty module tests — run from module root: tofu test

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
    target = data.aws_regions.enabled
    values = {
      names = ["us-east-1", "us-east-2", "us-west-2", "eu-west-1", "eu-central-1"]
    }
  }
}

variables {
  regions = ["us-east-1", "eu-west-1"]
}

################################################################################
# Detectors — one per Region
################################################################################

run "one_detector_per_region" {
  command = plan

  assert {
    condition     = length(aws_guardduty_detector.this) == 2
    error_message = "Exactly one detector must be created per requested Region"
  }

  assert {
    condition     = toset(keys(aws_guardduty_detector.this)) == toset(["us-east-1", "eu-west-1"])
    error_message = "Detectors must be keyed by Region"
  }

  assert {
    condition     = alltrue([for region, detector in aws_guardduty_detector.this : detector.region == region])
    error_message = "Each detector must be created in its own Region"
  }

  assert {
    condition     = alltrue([for detector in aws_guardduty_detector.this : detector.enable])
    error_message = "Every detector must be enabled"
  }

  assert {
    condition     = alltrue([for detector in aws_guardduty_detector.this : detector.finding_publishing_frequency == "FIFTEEN_MINUTES"])
    error_message = "Default finding_publishing_frequency must be FIFTEEN_MINUTES"
  }
}

run "finding_publishing_frequency_override" {
  command = plan

  variables {
    finding_publishing_frequency = "SIX_HOURS"
  }

  assert {
    condition     = alltrue([for detector in aws_guardduty_detector.this : detector.finding_publishing_frequency == "SIX_HOURS"])
    error_message = "finding_publishing_frequency must be applied to every detector"
  }
}

run "rejects_region_not_enabled_for_account" {
  command = plan

  variables {
    regions = ["us-east-1", "ap-south-1"]
  }

  expect_failures = [
    aws_guardduty_detector.this["ap-south-1"],
    aws_ecr_registry_scanning_configuration.this["ap-south-1"],
  ]
}

run "rejects_invalid_region_code" {
  command = plan

  variables {
    regions = ["us-east-1", "not-a-region"]
  }

  expect_failures = [
    var.regions,
  ]
}

run "rejects_duplicate_regions" {
  command = plan

  variables {
    regions = ["us-east-1", "us-east-1"]
  }

  expect_failures = [
    var.regions,
  ]
}

run "rejects_empty_regions" {
  command = plan

  variables {
    regions = []
  }

  expect_failures = [
    var.regions,
  ]
}

################################################################################
# Protection plans — every plan is explicit in every Region
################################################################################

run "default_protection_plans" {
  command = plan

  assert {
    condition     = length(aws_guardduty_detector_feature.this) == 2 * 6
    error_message = "Every protection plan must be managed explicitly in every Region"
  }

  assert {
    condition = alltrue([
      for key in [
        "us-east-1/S3_DATA_EVENTS", "us-east-1/EKS_AUDIT_LOGS", "us-east-1/EBS_MALWARE_PROTECTION",
        "us-east-1/RDS_LOGIN_EVENTS", "us-east-1/LAMBDA_NETWORK_LOGS",
        "eu-west-1/S3_DATA_EVENTS", "eu-west-1/EKS_AUDIT_LOGS", "eu-west-1/EBS_MALWARE_PROTECTION",
        "eu-west-1/RDS_LOGIN_EVENTS", "eu-west-1/LAMBDA_NETWORK_LOGS",
      ] : aws_guardduty_detector_feature.this[key].status == "ENABLED"
    ])
    error_message = "S3, EKS, Malware, RDS, and Lambda protection must be ENABLED by default"
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].status == "DISABLED"
    error_message = "Runtime Monitoring must be DISABLED by default"
  }

  assert {
    condition     = length(aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration) == 3
    error_message = "Runtime Monitoring must declare every agent management option explicitly"
  }

  assert {
    condition = alltrue([
      for config in aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration :
      config.status == "DISABLED"
    ])
    error_message = "Agent management options must be DISABLED while Runtime Monitoring is disabled"
  }

  assert {
    condition = alltrue([
      for key, feature in aws_guardduty_detector_feature.this :
      key != "${feature.region}/RUNTIME_MONITORING" ? length(feature.additional_configuration) == 0 : true
    ])
    error_message = "Only Runtime Monitoring carries additional_configuration"
  }

  assert {
    condition = alltrue([
      for key, feature in aws_guardduty_detector_feature.this :
      feature.region == split("/", key)[0] && feature.name == split("/", key)[1]
    ])
    error_message = "Feature resources must target their own Region and feature name"
  }
}

run "disable_protection_plan" {
  command = plan

  variables {
    s3_protection_enabled = false
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["us-east-1/S3_DATA_EVENTS"].status == "DISABLED"
    error_message = "Disabling S3 protection must write DISABLED rather than removing the feature"
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["eu-west-1/S3_DATA_EVENTS"].status == "DISABLED"
    error_message = "Disabling S3 protection must apply to every Region"
  }
}

run "runtime_monitoring_with_automated_agents" {
  command = plan

  variables {
    runtime_monitoring_enabled          = true
    runtime_monitoring_automated_agents = ["EKS_ADDON_MANAGEMENT", "EC2_AGENT_MANAGEMENT"]
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].status == "ENABLED"
    error_message = "Runtime Monitoring must be ENABLED when requested"
  }

  assert {
    condition = {
      for config in aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration :
      config.name => config.status
      } == {
      EKS_ADDON_MANAGEMENT         = "ENABLED"
      ECS_FARGATE_AGENT_MANAGEMENT = "DISABLED"
      EC2_AGENT_MANAGEMENT         = "ENABLED"
    }
    error_message = "Only the requested automated agents must be ENABLED"
  }
}

run "rejects_unknown_automated_agent" {
  command = plan

  variables {
    runtime_monitoring_enabled          = true
    runtime_monitoring_automated_agents = ["FOO_AGENT"]
  }

  expect_failures = [
    var.runtime_monitoring_automated_agents,
  ]
}

################################################################################
# Tagging
################################################################################

run "default_tags" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this["us-east-1"].tags["ManagedBy"] == "terraform"
    error_message = "Default ManagedBy tag must be present"
  }

  assert {
    condition     = aws_guardduty_detector.this["us-east-1"].tags["Module"] == "security/compliance"
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
    condition     = aws_guardduty_detector.this["eu-west-1"].tags["Environment"] == "prod"
    error_message = "User tags must be merged onto every detector"
  }

  assert {
    condition     = aws_guardduty_detector.this["eu-west-1"].tags["ManagedBy"] == "terraform"
    error_message = "Default tags must survive a user tag merge"
  }
}

################################################################################
# Outputs
################################################################################

run "outputs" {
  command = plan

  assert {
    condition     = output.regions == tolist(["eu-west-1", "us-east-1"])
    error_message = "regions output must be the sorted Region list"
  }

  assert {
    condition     = toset(keys(output.detector_ids)) == toset(["us-east-1", "eu-west-1"])
    error_message = "detector_ids must be keyed by Region"
  }

  assert {
    condition     = output.account_id == "123456789012"
    error_message = "account_id must come from the caller identity"
  }

  assert {
    condition     = output.protection_plans["S3_DATA_EVENTS"] == true && output.protection_plans["RUNTIME_MONITORING"] == false
    error_message = "protection_plans output must reflect the effective plan settings"
  }
}
