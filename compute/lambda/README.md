# AWS Lambda Module

This module creates an AWS Lambda function with broad runtime configuration support, optional IAM role creation, CloudWatch log group management, and optional integrations such as permissions, event source mappings, aliases, and function URL.

## Features

- Supports both `Zip` and `Image` package types
- Optional ECR repository for container image build pipelines
- Single-apply bootstrap image seeding for module-managed ECR repositories
- Supports standard Lambda and Lambda@Edge validation mode
- Optional IAM role creation or use of an existing role
- Optional CloudWatch log group creation with retention and KMS encryption
- Configurable invocation error-rate alarms, including Lambda@Edge execution Regions
- Optional invoke permissions (`aws_lambda_permission`)
- Optional event source mappings (`aws_lambda_event_source_mapping`)
- Optional aliases with weighted routing (`aws_lambda_alias`)
- Optional function URL with CORS configuration (`aws_lambda_function_url`)
- Consistent tagging with module defaults

## Usage

### Basic ZIP Function

```hcl
module "lambda" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name        = "orders-handler"
  package_type = "Zip"
  runtime     = "nodejs20.x"
  handler     = "index.handler"
  s3_bucket   = "my-lambda-artifacts"
  s3_key      = "orders-handler.zip"
}
```

### Container Image Function

```hcl
module "lambda_image" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name                            = "image-fn"
  package_type                    = "Image"
  architecture                    = "x86_64"
  ecr_repository_creation_enabled = true
  timeout                         = 30
  memory_size                     = 512
}
```

### Lambda@Edge-Compatible Function

```hcl
provider "aws" {
  region = "us-east-1"
}

module "edge_lambda" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name              = "edge-rewrite"
  lambda_at_edge_enabled = true

  package_type = "Zip"
  version_publishing_enabled      = true
  runtime      = "nodejs20.x"
  handler      = "index.handler"
  s3_bucket    = "my-lambda-artifacts"
  s3_key       = "edge-rewrite.zip"

  # Lambda@Edge constraints enforced by module validation:
  # - x86_64 architecture
  # - no env vars / VPC / layers / DLQ / EFS
  # - timeout <= 30, memory <= 3008
}
```

### With Integrations

```hcl
module "lambda_with_integrations" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/lambda?ref=v1.0.0"

  name         = "processor"
  package_type = "Zip"
  runtime      = "python3.12"
  handler      = "handler.main"
  s3_bucket    = "my-lambda-artifacts"
  s3_key       = "processor.zip"

  permissions = [
    {
      principal  = "events.amazonaws.com"
      source_arn = "arn:aws:events:us-east-1:123456789012:rule/my-rule"
    }
  ]

  event_source_mappings = [
    {
      event_source_arn = "arn:aws:sqs:us-east-1:123456789012:jobs-queue"
      batch_size       = 10
    }
  ]

  aliases = {
    live = {
      function_version = "1"
    }
  }

  function_url_enabled   = true
  function_url_auth_type = "AWS_IAM"
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Lambda function | `string` | n/a | yes |
| description | Description of the Lambda function | `string` | `null` | no |
| tags | Tags to assign to all resources | `map(string)` | `{}` | no |
| package_type | Package type (`Zip` or `Image`) | `string` | `"Zip"` | no |
| architecture | Lambda architecture | `string` | `"x86_64"` | no |
| version_publishing_enabled | Publish a version on update | `bool` | `false` | no |
| handler | Function handler (Zip only) | `string` | `null` | no |
| runtime | Function runtime (Zip only) | `string` | `null` | no |
| filename | Local ZIP package path | `string` | `null` | no |
| source_code_hash | Base64 SHA256 of package | `string` | `null` | no |
| s3_bucket | S3 bucket for package | `string` | `null` | no |
| s3_key | S3 key for package | `string` | `null` | no |
| image_uri | Image URI (Image only) | `string` | `null` | no |
| image_config | Image config override object | `object` | `null` | no |
| ecr_repository_creation_enabled | Create an ECR repository for built container image deployments | `bool` | `false` | no |
| ecr_repository_name | ECR repository name override | `string` | `null` | no |
| ecr_image_tag_mutability | ECR image tag mutability (`MUTABLE` or `IMMUTABLE`) | `string` | `"MUTABLE"` | no |
| ecr_scan_on_push_enabled | Scan images for vulnerabilities on push | `bool` | `true` | no |
| ecr_force_deletion_enabled | Allow deleting the ECR repository even when it contains images | `bool` | `false` | no |
| ecr_default_lifecycle_policy_enabled | Apply the built-in ECR lifecycle policy | `bool` | `false` | no |
| memory_size | Memory in MB | `number` | `128` | no |
| timeout | Timeout in seconds | `number` | `3` | no |
| kms_key_arn | KMS key ARN for environment encryption | `string` | `null` | no |
| layers | Lambda layer ARNs | `list(string)` | `[]` | no |
| reserved_concurrent_executions | Reserved concurrency | `number` | `null` | no |
| ephemeral_storage_size | `/tmp` size in MB | `number` | `512` | no |
| tracing_mode | X-Ray tracing mode | `string` | `"PassThrough"` | no |
| environment_variables | Environment variables map | `map(string)` | `{}` | no |
| vpc_config | VPC config object | `object` | `null` | no |
| dead_letter_target_arn | SQS/SNS dead letter target ARN | `string` | `null` | no |
| file_system_configs | EFS mount configs | `list(object)` | `[]` | no |
| snap_start_apply_on | SnapStart mode (`PublishedVersions`) | `string` | `null` | no |
| code_signing_config_arn | Code signing config ARN | `string` | `null` | no |
| role_creation_enabled | Create IAM role | `bool` | `true` | no |
| role_arn | Existing IAM role ARN | `string` | `null` | no |
| role_name | IAM role name override | `string` | `null` | no |
| role_path | IAM role path | `string` | `"/"` | no |
| role_permissions_boundary | IAM permissions boundary ARN | `string` | `null` | no |
| basic_execution_policy_enabled | Attach AWS basic execution policy | `bool` | `true` | no |
| vpc_execution_policy_enabled | Attach AWS VPC execution policy when vpc_config is set | `bool` | `true` | no |
| role_managed_policy_arns | Additional managed policy ARNs | `list(string)` | `[]` | no |
| role_inline_policies | Inline IAM policies map (`name => json`) | `map(string)` | `{}` | no |
| log_group_creation_enabled | Create CloudWatch log group | `bool` | `true` | no |
| log_group_name | Custom log group name | `string` | `null` | no |
| log_retention_days | Log retention in days | `number` | `30` | no |
| log_kms_key_id | KMS key for log group | `string` | `null` | no |
| permissions | Permission statements | `list(object)` | `[]` | no |
| event_source_mappings | Event source mappings | `list(object)` | `[]` | no |
| aliases | Lambda aliases keyed by alias name | `map(object)` | `{}` | no |
| function_url_enabled | Create function URL | `bool` | `false` | no |
| function_url_auth_type | Function URL auth type (`NONE` or `AWS_IAM`) | `string` | `"AWS_IAM"` | no |
| function_url_invoke_mode | Function URL invoke mode (`BUFFERED` or `RESPONSE_STREAM`) | `string` | `"BUFFERED"` | no |
| function_url_cors | Function URL CORS object | `object` | `null` | no |
| lambda_at_edge_enabled | Enable Lambda@Edge compatibility validations | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_name | Lambda function name |
| function_arn | Lambda function ARN |
| function_invoke_arn | Lambda function invoke ARN |
| function_qualified_arn | Lambda function qualified ARN |
| function_version | Latest function version |
| function_last_modified | Function last modified timestamp |
| role_arn | IAM role ARN used by function |
| log_group_name | CloudWatch log group name |
| log_group_arn | CloudWatch log group ARN (if created) |
| permission_statement_ids | Permission statement IDs by item index |
| event_source_mapping_ids | Event source mapping UUIDs by item index |
| alias_arns | Alias ARNs by alias name |
| function_url | Function URL when enabled |
| code_bucket_id | Auto-created code bucket name when enabled |
| code_bucket_arn | Auto-created code bucket ARN when enabled |
| code_object_key | Initial bootstrap object key when created |
| ecr_repository_arn | ECR repository ARN when enabled |
| ecr_repository_name | ECR repository name when enabled |
| ecr_repository_url | ECR repository URL when enabled |
| aws_account_id | AWS account ID where resources are deployed |
| region | AWS region where resources are deployed |

## Notes

- Lambda@Edge deployments must be created in `us-east-1`.
- The module enforces key Lambda@Edge constraints when `lambda_at_edge_enabled = true`.
- For `Zip` package type, provide either `filename` or (`s3_bucket` + `s3_key`).
- For `Image` package type, provide `image_uri`, or enable `ecr_repository_creation_enabled` so the module can seed a Lambda-compatible bootstrap image in the module-owned ECR repository during apply.
- Bootstrap image seeding uses AWS CLI and standard POSIX tools on the Terraform/OpenTofu runner. When AWS CLI is missing, the module attempts a package-manager install with sudo/root access, then falls back to installing AWS CLI v2 in a temporary directory with Python 3.

## Invocation error-rate alarms

`cloudwatch_alarms_creation_enabled` defaults to true to monitor
`100 * SUM(Errors) / SUM(Invocations)` for the function, across all versions and
aliases. The alarm defaults to >=1% over one 5-minute period. Zero invocations
produce zero; missing data is non-breaching because idle functions emit no metrics.
This monitors Lambda invocation failures, not application HTTP response codes or throttles.

Both Ravion and direct Terraform callers get alarms by default; set the toggle to false to opt out. Set
`cloudwatch_alarm_actions` to a same-region SNS topic ARN list, or route CloudWatch
alarm events using an externally managed EventBridge relay. No notification
destination is created automatically. `cloudwatch_ok_actions` is optional.

For Lambda@Edge, the module uses the `us-east-1.` function-name prefix and always
creates an alarm in the origin Region. Set `cloudwatch_alarm_additional_regions`
to every other execution Region to monitor real edge traffic; origin-only alarms
do not provide global coverage. Configure `cloudwatch_alarm_actions_by_region`
and `cloudwatch_ok_actions_by_region` for regional SNS destinations. Add regions
as traffic expands. Existing manually created alarms should be imported into the
matching resource address before Terraform takes ownership.

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| cloudwatch_alarms_creation_enabled | `bool` | `true` | Enable invocation error-rate alarms. |
| cloudwatch_alarm_error_rate_threshold | `number` | `1` | Percentage threshold, >0 and <=100. |
| cloudwatch_alarm_period | `number` | `300` | 60, 300, 900, or 3600 seconds. |
| cloudwatch_alarm_evaluation_periods | `number` | `1` | Consecutive breaching periods, covering at most one day. |
| cloudwatch_alarm_additional_regions | `list(string)` | `[]` | Additional Edge execution Regions. |
| cloudwatch_alarm_actions | `list(string)` | `[]` | Default ALARM actions. |
| cloudwatch_ok_actions | `list(string)` | `[]` | Default OK actions. |
| cloudwatch_alarm_actions_by_region | `map(list(string))` | `{}` | Per-Region ALARM action overrides. |
| cloudwatch_ok_actions_by_region | `map(list(string))` | `{}` | Per-Region OK action overrides. |

`cloudwatch_alarm_arns` outputs a map of Region to alarm ARN.

See [AWS Lambda metrics](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html).
