# ECR registry scanning

Enables Basic image scanning on push for every private ECR repository in the selected AWS Regions. The registry-wide `*` rule covers existing and future repositories, including repositories used by ECS, EKS, EC2, and Lambda.

## Usage

```hcl
module "ecr_scanning" {
  source = "git::https://github.com/ravionhq/modules.git//security/ecr_scanning?ref=rvn-ecr-scanning@0.1.0"

  regions = ["us-west-2", "us-east-1"]
}
```

The `rvn-ecr-scanning` Ravion definition exposes the AWS account, runner Region, and Regions to configure. Deploy one instance per account with all required Regions, or use instances with non-overlapping Regions.

## Ownership and existing configuration

ECR has one scanning configuration per account per Region. This module owns the entire configuration in each selected Region; keep it separate from repository and service modules, and do not manage the same Region from multiple Terraform states.

Applying writes `BASIC` scanning with a `SCAN_ON_PUSH` rule matching `*`, including when scanning was previously configured manually. Existing Enhanced scanning or custom filters are replaced, so review those settings before adopting this module. Repository-level `scan_on_push` flags alone do not declare the registry rule checked by compliance tools such as OneLeet.

Removing a Region or destroying the module resets its registry to Basic scanning without rules. It does not delete repositories or images. Basic scanning checks operating-system vulnerabilities on new image pushes; it does not enable continuous scanning or retroactively scan all existing images.

The registry-scanning resource does not support tags.

## Requirements

| Name | Version |
| --- | --- |
| OpenTofu/Terraform | >= 1.10.0 |
| AWS provider | >= 6.0 |

All selected Regions must already be enabled for the account. The execution role needs `ec2:DescribeRegions`, `ecr:GetRegistryScanningConfiguration`, and `ecr:PutRegistryScanningConfiguration`.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| regions | Unique, non-empty list of AWS Regions where every private repository scans on push. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| --- | --- |
| regions | Sorted list of configured Regions. |
| registry_ids | Map of Region to ECR registry ID (AWS account ID). |

## Verification

```sh
tofu init -backend=false
tofu validate
tofu test
```

Tests use a mocked AWS provider and do not change AWS resources.

## References

- [ECR scanning filters](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-filters.html)
- [Terraform registry scanning resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_registry_scanning_configuration)
