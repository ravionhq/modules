# AWS compliance module

Manages GuardDuty threat detection, registry-wide Basic ECR image scanning on push, and regional CloudTrail audit trails for one AWS account. Deploy `rvn-aws-compliance` once per account with all required Regions. The Regions list controls all three services; the runner Region hosts the shared log bucket.

## Features

- Registry-wide ECR Basic `SCAN_ON_PUSH` with a `*` filter for all current and future private repositories, including Lambda image repositories.
- One validated single-Region CloudTrail management-event trail per selected Region, sharing private, versioned log storage in the runner Region.
- One `aws_guardduty_detector` per Region, driven by the AWS provider's per-resource `region` argument (no provider alias per Region).
- Fails at plan time when a requested Region is not enabled (opted in) for the account.
- Explicit per-Region protection plans: S3 Protection, EKS Protection, Malware Protection for EC2, RDS Protection, Lambda Protection, and Runtime Monitoring with automated agent management for EKS, ECS Fargate, and EC2.
- Configurable finding publishing frequency.
- Default `ManagedBy` / `Module` tags merged with caller-supplied tags.

## Usage

### Enable the baseline in every Region you use

```hcl
module "compliance" {
  source = "git::https://github.com/ravionhq/modules.git//security/compliance?ref=rvn-aws-compliance@0.1.0"

  regions = ["us-east-1", "us-west-2", "eu-west-1"]

  tags = {
    Environment = "prod"
  }
}
```

### Turn on Runtime Monitoring with managed agents

```hcl
module "compliance" {
  source = "git::https://github.com/ravionhq/modules.git//security/compliance?ref=rvn-aws-compliance@0.1.0"

  regions = ["us-east-1"]

  runtime_monitoring_enabled          = true
  runtime_monitoring_automated_agents = ["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT"]
}
```

### Basic GuardDuty detection with ECR scanning

```hcl
module "compliance" {
  source = "git::https://github.com/ravionhq/modules.git//security/compliance?ref=rvn-aws-compliance@0.1.0"

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

The AWS provider 6.x per-resource `region` argument is required. The credentials used for the apply need `ecr:GetRegistryScanningConfiguration`, `ecr:PutRegistryScanningConfiguration`, GuardDuty administration permissions plus `ec2:DescribeRegions` (used to verify the requested Regions are enabled) and `iam:CreateServiceLinkedRole` for the GuardDuty and Malware Protection service-linked roles on first use.

## Inputs

CloudTrail is enabled by default: a single-Region trail in each selected Region records read/write management events with log file validation and no data events. The dedicated shared S3 bucket stays in the runner Region, with versioning, bucket-owner-enforced ownership and SSE-S3 encryption by default.

Include us-east-1 in Regions to capture IAM changes and other global service events (CloudFront and the STS global endpoint). Only that trail includes global service events; us-east-1 is never added automatically. STS regional-endpoint events are recorded in their respective Regions.

The first copy of management events per Region is free; an existing trail recording those events makes this a paid additional copy in that Region. Disable CloudTrail when an organization trail already provides coverage. S3 storage and optional KMS usage incur charges.

Current and noncurrent versions expire after the configured retention period (365 days by default); 0 disables expiry. Current-object expiry creates a delete marker before noncurrent expiry applies. Destroy, including disabling CloudTrail, fails while logs or versions remain in the bucket because force deletion is disabled.

A supplied KMS key encrypts trail deliveries and bucket objects. It must be in the bucket's runner Region, even for trails in other Regions. Its key policy must allow cloudtrail.amazonaws.com for every selected trail; this module does not manage that policy.

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| `regions` | Regions for GuardDuty, ECR scanning and CloudTrail. Include us-east-1 for IAM changes. Each must be enabled for the account. | `list(string)` | n/a | yes |
| `cloudtrail_enabled` | Create a single-Region management-event trail in each selected Region. | `bool` | `true` | no |
| `cloudtrail_log_retention_days` | Current and noncurrent log expiry; 0 keeps logs forever. | `number` | `365` | no |
| `cloudtrail_kms_key_arn` | Key in the bucket's runner Region whose policy permits encryption for every trail; null uses SSE-S3. | `string` | `null` | no |
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
| `regions` | Sorted list of Regions covered by GuardDuty, ECR scanning and optional CloudTrail. |
| `cloudtrail_arns` | Map of Region to trail ARN, empty when disabled. |
| `cloudtrail_bucket_name` | Audit log bucket name, or null when disabled. |
| `cloudtrail_bucket_arn` | Audit log bucket ARN, or null when disabled. |
| `detector_ids` | Map of Region to detector ID. |
| `detector_arns` | Map of Region to detector ARN. |
| `account_id` | AWS account ID where the baseline is managed. |
| `registry_ids` | Map of Region to ECR registry ID. |
| `protection_plans` | Map of protection plan feature name to enabled flag. |

## ECR scanning and ownership

The module always enables Basic scanning with a `SCAN_ON_PUSH` registry rule matching `*` in each selected Region. This covers existing and future repositories, including those used by Lambda, ECS, EKS, and EC2. It declares the registry configuration checked by OneLeet instead of relying only on individual repositories' `scan_on_push` flags.

Basic scanning checks operating-system vulnerabilities when new images are pushed; it does not enable continuous scanning or retroactively scan all existing images. Applying replaces existing Enhanced scanning or custom registry filters with this Basic configuration, so review current settings before adoption. Existing manually configured registries can be managed by applying the module.

ECR registry scanning and GuardDuty are account/Region-wide settings. Maintain one Terraform owner per account and Region. Do not deploy overlapping compliance modules or manage these resources from individual network or service modules. The ECR scanning resource does not support tags.

Removing a Region or destroying the module resets ECR to Basic scanning without registry rules. ECR repositories and images are retained.

## Existing GuardDuty detectors

Import existing detectors before applying, preserving threat detection and findings. Do not disable GuardDuty to make module adoption possible. The selected protection-plan inputs will become authoritative.

## Notes

- **One detector per Region.** AWS allows exactly one GuardDuty detector per account per Region. If GuardDuty is already enabled in a Region, import the existing detector instead of creating a new one:

  ```bash
  tofu import 'module.compliance.aws_guardduty_detector.this["us-east-1"]' <detector-id>
  ```

  Detector features are imported as `<detector-id>/<feature-name>`.

- **Opt-in Regions.** GuardDuty cannot be enabled in a Region the account has not opted into. The module checks the account's enabled Regions and fails the plan with a clear message for any Region that is not enabled.
- **Disabling.** Removing a Region from `regions` destroys that Region's detector, which disables GuardDuty there and discards its findings. Setting a protection plan to `false` keeps the detector and writes the plan as `DISABLED`; it does not affect ECR scanning.
- **Findings delivery.** GuardDuty publishes findings to EventBridge in each Region. Central aggregation (S3 export, Security Hub, a delegated administrator account) is out of scope for this module.
- **Cost.** Protection plans are billed per Region by the volume of data analysed. Runtime Monitoring adds agent cost per workload and is therefore disabled by default.

## Testing

```bash
cd security/compliance
tofu init -backend=false
tofu validate
tofu test
```

The test suite uses a mocked AWS provider and does not create real resources.
