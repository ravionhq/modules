# AWS GuardDuty Module

Enables Amazon GuardDuty threat detection in a list of AWS Regions for one account. The module creates one GuardDuty detector per Region and explicitly manages every protection plan (S3, EKS, Malware, RDS, Lambda, Runtime Monitoring) as `ENABLED` or `DISABLED` in each Region, so the effective GuardDuty configuration is fully declared in code. Continuous threat detection across all in-use Regions is a common SOC 2 monitoring control.

## Features

- One `aws_guardduty_detector` per Region, driven by the AWS provider's per-resource `region` argument (no provider alias per Region).
- Fails at plan time when a requested Region is not enabled (opted in) for the account.
- Explicit per-Region protection plans: S3 Protection, EKS Protection, Malware Protection for EC2, RDS Protection, Lambda Protection, and Runtime Monitoring with automated agent management for EKS, ECS Fargate, and EC2.
- Configurable finding publishing frequency.
- Default `ManagedBy` / `Module` tags merged with caller-supplied tags.

## Usage

### Enable GuardDuty in every Region you use

```hcl
module "guardduty" {
  source = "git::https://github.com/ravionhq/modules.git//security/guardduty?ref=v1.0.0"

  regions = ["us-east-1", "us-west-2", "eu-west-1"]

  tags = {
    Environment = "prod"
  }
}
```

### Turn on Runtime Monitoring with managed agents

```hcl
module "guardduty" {
  source = "git::https://github.com/ravionhq/modules.git//security/guardduty?ref=v1.0.0"

  regions = ["us-east-1"]

  runtime_monitoring_enabled          = true
  runtime_monitoring_automated_agents = ["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT"]
}
```

### Foundational detection only

```hcl
module "guardduty" {
  source = "git::https://github.com/ravionhq/modules.git//security/guardduty?ref=v1.0.0"

  regions = ["us-east-1", "eu-central-1"]

  s3_protection_enabled      = false
  eks_protection_enabled     = false
  malware_protection_enabled = false
  rds_protection_enabled     = false
  lambda_protection_enabled  = false
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| OpenTofu | >= 1.10.0 |
| aws | >= 6.0 |

The AWS provider 6.x per-resource `region` argument is required. The credentials used for the apply need GuardDuty administration permissions plus `ec2:DescribeRegions` (used to verify the requested Regions are enabled) and `iam:CreateServiceLinkedRole` for the GuardDuty and Malware Protection service-linked roles on first use.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| `regions` | AWS Regions where GuardDuty is enabled. Each must be enabled for the account. | `list(string)` | n/a | yes |
| `finding_publishing_frequency` | Export cadence for updated findings: `FIFTEEN_MINUTES`, `ONE_HOUR`, or `SIX_HOURS`. | `string` | `"FIFTEEN_MINUTES"` | no |
| `s3_protection_enabled` | Enable S3 Protection (`S3_DATA_EVENTS`). | `bool` | `true` | no |
| `eks_protection_enabled` | Enable EKS Protection (`EKS_AUDIT_LOGS`). | `bool` | `true` | no |
| `malware_protection_enabled` | Enable Malware Protection for EC2 (`EBS_MALWARE_PROTECTION`). | `bool` | `true` | no |
| `rds_protection_enabled` | Enable RDS Protection (`RDS_LOGIN_EVENTS`). | `bool` | `true` | no |
| `lambda_protection_enabled` | Enable Lambda Protection (`LAMBDA_NETWORK_LOGS`). | `bool` | `true` | no |
| `runtime_monitoring_enabled` | Enable Runtime Monitoring (`RUNTIME_MONITORING`). | `bool` | `false` | no |
| `runtime_monitoring_automated_agents` | Workload types with GuardDuty-managed security agents: `EKS_ADDON_MANAGEMENT`, `ECS_FARGATE_AGENT_MANAGEMENT`, `EC2_AGENT_MANAGEMENT`. Ignored unless Runtime Monitoring is enabled. | `list(string)` | all three | no |
| `tags` | Additional tags applied to every detector. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| `regions` | Sorted list of Regions where GuardDuty is enabled. |
| `detector_ids` | Map of Region to detector ID. |
| `detector_arns` | Map of Region to detector ARN. |
| `account_id` | AWS account ID that owns the detectors. |
| `protection_plans` | Map of protection plan feature name to enabled flag. |

## Notes

- **One detector per Region.** AWS allows exactly one GuardDuty detector per account per Region. If GuardDuty is already enabled in a Region, import the existing detector instead of creating a new one:

  ```bash
  tofu import 'module.guardduty.aws_guardduty_detector.this["us-east-1"]' <detector-id>
  ```

  Detector features are imported as `<detector-id>/<feature-name>`.

- **Opt-in Regions.** GuardDuty cannot be enabled in a Region the account has not opted into. The module checks the account's enabled Regions and fails the plan with a clear message for any Region that is not enabled.
- **Disabling.** Removing a Region from `regions` destroys that Region's detector, which disables GuardDuty there and discards its findings. Setting a protection plan to `false` keeps the detector and writes the plan as `DISABLED`.
- **Findings delivery.** GuardDuty publishes findings to EventBridge in each Region. Central aggregation (S3 export, Security Hub, a delegated administrator account) is out of scope for this module.
- **Cost.** Protection plans are billed per Region by the volume of data analysed. Runtime Monitoring adds agent cost per workload and is therefore disabled by default.

## Testing

```bash
cd security/guardduty
tofu init -backend=false
tofu test
```

The test suite uses a mocked AWS provider and does not create real resources.
