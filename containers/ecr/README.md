# Amazon ECR Repository

Creates a private Amazon ECR repository for container images with configurable image scanning, cleanup, encryption, and repository access.

## Usage

```hcl
module "ecr" {
  source = "git::https://github.com/ravionhq/modules.git//containers/ecr?ref=v1.0.0"

  name = "team/api"
}
```

## Requirements

| Name | Version |
| --- | --- |
| OpenTofu/Terraform | >= 1.10.0 |
| AWS provider | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `name` | Name of the ECR repository. Must be lowercase, 2-256 characters, and may contain letters, numbers, hyphens, underscores, periods, and forward slashes. | `string` | n/a | yes |
| `tags` | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| `image_tag_mutability` | The tag mutability setting for the repository. Set to IMMUTABLE to prevent tags from being overwritten. | `string` | `"MUTABLE"` | no |
| `image_scan_on_push_enabled` | Indicates whether images are scanned for vulnerabilities after being pushed. | `bool` | `true` | no |
| `force_delete_enabled` | If true, the repository will be deleted even if it contains images. Use with caution. | `bool` | `false` | no |
| `encryption_type` | The encryption type for the repository. AES256 uses AWS-managed keys; KMS uses a customer-managed KMS key. | `string` | `"AES256"` | no |
| `kms_key_arn` | The ARN of the KMS key to use when encryption_type is KMS. If null with KMS, an AWS-managed KMS key is used. | `string` | `null` | no |
| `lifecycle_policy` | A raw JSON lifecycle policy document. If set, takes precedence over the built-in lifecycle rules below. | `string` | `null` | no |
| `default_lifecycle_policy_enabled` | Apply a built-in lifecycle policy that expires untagged images and caps the number of images retained, tagged or untagged. Ignored if lifecycle_policy is set. | `bool` | `false` | no |
| `untagged_image_expiry_days` | Number of days after which untagged images are expired. Used only when default_lifecycle_policy_enabled is true. | `number` | `14` | no |
| `max_tagged_image_count` | Maximum number of images to retain, tagged or untagged. Older images beyond this count are expired. Used only when default_lifecycle_policy_enabled is true. | `number` | `100` | no |
| `repository_policy` | A raw JSON repository policy document. If set, takes precedence over allowed_pull_principal_arns and allowed_push_principal_arns. | `string` | `null` | no |
| `allowed_pull_principal_arns` | A list of IAM principal ARNs granted pull access (read) to the repository. Used to generate a repository policy when repository_policy is null. | `list(string)` | `[]` | no |
| `allowed_push_principal_arns` | A list of IAM principal ARNs granted push access (read and write) to the repository. Used to generate a repository policy when repository_policy is null. | `list(string)` | `[]` | no |
| `region` | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |

## Outputs

| Name | Description |
| --- | --- |
| `repository_arn` | The ARN of the ECR repository. |
| `repository_name` | The name of the ECR repository. |
| `repository_url` | The URL of the ECR repository (in the form `<aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository_name>`). |
| `registry_id` | The registry ID where the repository was created. |
| `aws_account_id` | The AWS account ID where the resources are deployed. |
| `region` | The AWS region where the resources are deployed. |
