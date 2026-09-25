# AWS Secret Module

Generates a random value and stores it in SSM Parameter Store (SecureString) or AWS Secrets Manager. The value is produced by an ephemeral `random_password` and written through write-only arguments (`value_wo` / `secret_string_wo`), so it is never stored in Terraform state or plan files. Only the ARN and name are exported.

## Features

- SSM Parameter Store (default) or Secrets Manager storage.
- Value never in state, plans, or outputs.
- Rotation by incrementing `rotation_version`.
- Optional customer managed KMS key.

## Usage

### Parameter Store (default)

```hcl
module "master_key" {
  source = "git::https://github.com/ravionhq/modules.git//security/secret?ref=rvn-aws-secret@0.1.0"

  name = "myapp/production/master-key"
}

# ECS container definition
secrets = [{
  name      = "MASTER_KEY"
  valueFrom = module.master_key.arn
}]
```

### Secrets Manager

```hcl
module "session_secret" {
  source = "git::https://github.com/ravionhq/modules.git//security/secret?ref=rvn-aws-secret@0.1.0"

  name   = "myapp/production/session-secret"
  store  = "secrets_manager"
  length = 64
}
```

### Rotating the value

```hcl
module "master_key" {
  # ...
  rotation_version = 2
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu | >= 1.11.0 |
| aws | >= 6.0 |
| random | >= 3.7 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Parameter or secret name. A leading slash is added for Parameter Store and removed for Secrets Manager. | `string` | n/a | yes |
| store | `parameter_store` or `secrets_manager`. | `string` | `"parameter_store"` | no |
| description | Description of the parameter or secret. | `string` | generated | no |
| length | Characters in the generated value (16-512). | `number` | `32` | no |
| special_characters | Include special characters. | `bool` | `false` | no |
| rotation_version | Change to generate and store a new value. | `number` | `1` | no |
| kms_key_id | KMS key ID, ARN, or alias. Defaults to the AWS managed key. | `string` | `null` | no |
| recovery_window_in_days | Secrets Manager recovery window (0 or 7-30). | `number` | `30` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |
| region | AWS region. Defaults to the provider region. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| arn | ARN of the parameter or secret. Use as `valueFrom` in ECS task secrets. |
| name | Name of the parameter or secret. |
| store | Store used. |
| rotation_version | Version of the stored value. |
| aws_account_id | AWS account ID. |
| region | AWS region. |
