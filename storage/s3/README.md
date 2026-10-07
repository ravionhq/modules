# S3 Bucket Module

This module creates an AWS S3 bucket with enterprise-grade security best practices including public access blocking, server-side encryption (SSE-S3 or SSE-KMS), versioning, CORS rules, lifecycle rules, and configurable bucket policies.

## Features

- S3 bucket with configurable naming and force destroy options
- Public access blocking (all four settings enabled by default)
- Server-side encryption (SSE-S3 AES256 or SSE-KMS with optional Bucket Keys) with SSE-C uploads blocked
- Versioning support for object version management
- CORS rules for browser-based cross-origin access
- Comprehensive lifecycle rules for storage class transitions and expiration
- Pre-built policy templates for common use cases (ALB/NLB logs, VPC Flow Logs, CloudFront OAC, HTTPS enforcement)
- Custom bucket policy support with automatic merging
- Automatic tag propagation with module defaults

## Usage

### Basic Bucket

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name = "my-application-bucket"

  tags = {
    Environment = "production"
  }
}
```

### Bucket with KMS Encryption

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name       = "my-encrypted-bucket"
  kms_key_id = aws_kms_key.s3.arn

  tags = {
    Environment = "production"
  }
}
```

### Bucket with Versioning

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name               = "my-versioned-bucket"
  versioning_enabled = true

  tags = {
    Environment = "production"
  }
}
```

### Bucket with Lifecycle Rules

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name               = "my-lifecycle-bucket"
  versioning_enabled = true

  lifecycle_rules = [
    {
      id     = "expire-old-objects"
      prefix = "logs/"
      expiration = {
        days = 90
      }
    },
    {
      id     = "archive-to-glacier"
      prefix = "backups/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    },
    {
      id = "cleanup-incomplete-uploads"
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Bucket with CORS Rules

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name = "my-cors-bucket"

  cors_rules = [
    {
      allowed_methods = ["GET", "PUT"]
      allowed_origins = ["https://app.example.com"]
      allowed_headers = ["*"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### ALB Access Logs Bucket

```hcl
module "alb_logs" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name             = "my-alb-access-logs"
  force_destroy_enabled = true
  policy_templates = ["alb_access_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 90
      }
    }
  ]

  tags = {
    Purpose = "ALB Access Logs"
  }
}

# Use with ALB module
module "alb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/alb?ref=v1.0.0"

  name                   = "main"
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.public_subnet_ids
  access_logs_enabled     = true
  access_logs_bucket_arn = module.alb_logs.bucket_arn
}
```

### VPC Flow Logs Bucket

```hcl
module "flow_logs" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name             = "my-vpc-flow-logs"
  force_destroy_enabled = true
  policy_templates = ["vpc_flow_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 30
      }
    }
  ]

  tags = {
    Purpose = "VPC Flow Logs"
  }
}
```

### NLB Access Logs Bucket

```hcl
module "nlb_logs" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name             = "my-nlb-access-logs"
  force_destroy_enabled = true
  policy_templates = ["nlb_access_logs", "deny_insecure_transport"]

  lifecycle_rules = [
    {
      id = "expire-logs"
      expiration = {
        days = 90
      }
    }
  ]

  tags = {
    Purpose = "NLB Access Logs"
  }
}
```

### Private Bucket for CloudFront OAC

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name = "private-attachments"

  policy_templates = ["deny_insecure_transport", "cloudfront_oac_read"]
  cloudfront_distribution_arns = [
    "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
  ]

  tags = {
    Environment = "production"
  }
}
```

Create or apply the CloudFront distribution first, then add its distribution ARN here so the private bucket can authorize that exact distribution.

### Full Configuration Example

```hcl
module "s3" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//storage/s3?ref=v1.0.0"

  name          = "my-full-config-bucket"
  force_destroy_enabled = false

  # Encryption
  kms_key_id         = aws_kms_key.s3.arn
  bucket_key_enabled = true

  # Versioning
  versioning_enabled = true

  # Public access block (all enabled by default)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Lifecycle rules
  lifecycle_rules = [
    {
      id = "archive-and-expire"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 365
      }
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    }
  ]

  # Policies
  policy_templates = ["deny_insecure_transport"]

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                 S3 Bucket                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        Server-Side Encryption                          │  │
│  │  • SSE-S3 (AES256) - Default                                          │  │
│  │  • SSE-KMS with optional Bucket Keys for cost reduction               │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │  Public Access Block │  │     Versioning       │  │  Lifecycle Rules   │  │
│  │  • Block ACLs        │  │  • Enabled/Disabled  │  │  • Transitions     │  │
│  │  • Block policies    │  │  • Version tracking  │  │  • Expiration      │  │
│  │  • Ignore ACLs       │  │                      │  │  • Abort uploads   │  │
│  │  • Restrict public   │  │                      │  │  • Noncurrent ver  │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                          Bucket Policy                                  │  │
│  │  • Policy templates (ALB/NLB logs, VPC Flow Logs, HTTPS enforcement)  │  │
│  │  • Custom policy support with automatic merging                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                         STORAGE/S3 TERRAFORM MODULE                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │    BUCKET CONFIGURATION         │   │        ENCRYPTION                       │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • force_destroy_enabled         │   │ • kms_key_id                            │  ║
║  │ • tags                      │   │                                 │   │ • bucket_key_enabled                    │  ║
║  └──────────────┬──────────────┘   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                 │                                                                                                      ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "storage/s3" }                                       │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • use_kms_encryption = var.kms_key_id != null                                                             │   │  ║
║  │  │ • create_lifecycle_configuration = length(var.lifecycle_rules) > 0                                        │   │  ║
║  │  │ • bucket policy is created when policy_templates or custom_policy are set, unless overridden                         │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ POLICY PROCESSING:                                                                                         │   │  ║
║  │  │ • policy_template_statements = flatten(policy templates)                                                   │   │  ║
║  │  │ • custom_policy_statements = parsed custom policy statements                                               │   │  ║
║  │  │ • all_policy_statements = concat(template_statements, custom_statements)                                   │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │     VERSIONING              │   │       PUBLIC ACCESS BLOCK       │   │       LIFECYCLE RULES                   │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • versioning_enabled        │   │ • block_public_acls             │   │ • lifecycle_rules[]:                    │  ║
║  │                             │   │ • block_public_policy           │   │   - id, enabled, prefix, tags          │  ║
║  │                             │   │ • ignore_public_acls            │   │   - expiration (days/date)             │  ║
║  │                             │   │ • restrict_public_buckets       │   │   - transitions[]                      │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   │   - noncurrent_version_expiration      │  ║
║                                                                          │   - noncurrent_version_transitions[]   │  ║
║                                                                          │   - abort_incomplete_multipart_upload  │  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                           BUCKET POLICY                                                           │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • policy_templates[]:                                                                                            │  ║
║  │   - deny_insecure_transport: Enforces HTTPS-only access                                                          │  ║
║  │   - alb_access_logs: Allows ALB to write access logs                                                             │  ║
║  │   - nlb_access_logs: Allows NLB to write access logs                                                             │  ║
║  │   - vpc_flow_logs: Allows VPC Flow Logs delivery                                                                 │  ║
║  │                                                                                                                  │  ║
║  │ • custom_policy: JSON policy document (merged with templates)                                                    │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                        │
                                                        ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                        aws_s3_bucket.this                                                    │    ║
║    │                                          (CORE RESOURCE)                                                     │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ • bucket = var.name                                                                                          │    ║
║    │ • force_destroy = var.force_destroy_enabled                                                                  │    ║
║    │ • tags = merged tags with Name                                                                               │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║           ┌─────────────────────────┬─────────────────────┼─────────────────────┬─────────────────────┐                ║
║           │                         │                     │                     │                     │                ║
║           ▼                         ▼                     ▼                     ▼                     ▼                ║
║    ┌────────────────┐    ┌────────────────────┐   ┌────────────────┐   ┌────────────────┐   ┌────────────────────┐    ║
║    │aws_s3_bucket_  │    │aws_s3_bucket_      │   │aws_s3_bucket_  │   │aws_s3_bucket_  │   │aws_s3_bucket_      │    ║
║    │public_access_  │    │server_side_        │   │versioning      │   │lifecycle_      │   │policy.this[0]      │    ║
║    │block.this      │    │encryption_         │   │.this           │   │configuration   │   │                    │    ║
║    │                │    │configuration.this  │   │                │   │.this[0]        │   │(count: 0 or 1)     │    ║
║    ├────────────────┤    ├────────────────────┤   ├────────────────┤   ├────────────────┤   ├────────────────────┤    ║
║    │• block_public  │    │• sse_algorithm:    │   │• status:       │   │• rule[]:       │   │• Merged policy     │    ║
║    │  _acls         │    │  AES256 or aws:kms │   │  Enabled or    │   │  - filter      │   │  statements from   │    ║
║    │• block_public  │    │• kms_master_key_id │   │  Disabled      │   │  - expiration  │   │  templates and     │    ║
║    │  _policy       │    │• bucket_key_       │   │                │   │  - transition  │   │  custom policy     │    ║
║    │• ignore_public │    │  enabled           │   │                │   │  - noncurrent  │   │                    │    ║
║    │  _acls         │    │                    │   │                │   │  - abort_mpu   │   │• depends_on:       │    ║
║    │• restrict_     │    │                    │   │                │   │                │   │  public_access_    │    ║
║    │  public_buckets│    │                    │   │                │   │                │   │  block             │    ║
║    └────────────────┘    └────────────────────┘   └────────────────┘   └────────────────┘   └────────────────────┘    ║
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                           DATA SOURCES                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ • aws_caller_identity.current  - Account ID for policy templates                                             │    ║
║    │ • aws_region.current           - Region for policy templates                                                 │    ║
║    │ • aws_elb_service_account.current - ELB service ARN for ALB log delivery                                     │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                        │
                                                        ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │           S3 BUCKET                     │   │           BUCKET POLICY                 │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • bucket_id                             │   │ • bucket_policy                         │                            ║
║  │ • bucket_arn                            │   │                                         │                            ║
║  │ • bucket_domain_name                    │   └─────────────────────────────────────────┘                            ║
║  │ • bucket_regional_domain_name           │                                                                          ║
║  │ • bucket_hosted_zone_id                 │   ┌─────────────────────────────────────────┐                            ║
║  │ • bucket_region                         │   │           VERSIONING                    │                            ║
║  └─────────────────────────────────────────┘   ├─────────────────────────────────────────┤                            ║
║                                                │ • versioning_enabled                    │                            ║
║  ┌─────────────────────────────────────────┐   └─────────────────────────────────────────┘                            ║
║  │           ENCRYPTION                    │                                                                          ║
║  ├─────────────────────────────────────────┤                                                                          ║
║  │ • encryption_algorithm                  │                                                                          ║
║  │ • kms_key_id                            │                                                                          ║
║  └─────────────────────────────────────────┘                                                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              DATA FLOW DIAGRAM                                                         ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║                                        ┌─────────────────────────┐                                                     ║
║                                        │       var.name          │                                                     ║
║                                        │    (bucket name)        │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║  var.force_destroy_enabled ─────────────► aws_s3_bucket.this ◄───────────────────── local.tags                        ║
║                                                     │                                                                  ║
║                                                     │                                                                  ║
║           ┌─────────────────────────────────────────┼─────────────────────────────────────────┐                        ║
║           │                                         │                                         │                        ║
║           ▼                                         ▼                                         ▼                        ║
║  ┌────────────────────┐              ┌────────────────────────┐              ┌────────────────────────┐               ║
║  │ var.block_public_* │              │ var.kms_key_id         │              │ var.versioning_enabled │               ║
║  │ (4 settings)       │              │ var.bucket_key_enabled │              │                        │               ║
║  └─────────┬──────────┘              └───────────┬────────────┘              └───────────┬────────────┘               ║
║            │                                     │                                       │                            ║
║            ▼                                     ▼                                       ▼                            ║
║  aws_s3_bucket_public_        aws_s3_bucket_server_side_             aws_s3_bucket_versioning                        ║
║  access_block.this            encryption_configuration.this          .this                                           ║
║                                                                                                                        ║
║                                                                                                                        ║
║  ┌────────────────────────────────────┐              ┌──────────────────────────────────────────┐                     ║
║  │     var.lifecycle_rules[]          │              │ var.policy_templates[]                   │                     ║
║  │  • id, prefix, tags                │              │ var.custom_policy                        │                     ║
║  │  • expiration, transitions         │              │                                          │                     ║
║  │  • noncurrent_version_*            │              │                                          │                     ║
║  └─────────────┬──────────────────────┘              └──────────────────┬───────────────────────┘                     ║
║                │                                                        │                                              ║
║                │ (count: 0 or 1)                                        │ (count: 0 or 1)                              ║
║                ▼                                                        ▼                                              ║
║  aws_s3_bucket_lifecycle_                           ┌──────────────────────────────────┐                              ║
║  configuration.this[0]                              │ local.policy_template_statements │                              ║
║                                                     │ local.custom_policy_statements   │                              ║
║                                                     │              │                   │                              ║
║                                                     │              ▼                   │                              ║
║                                                     │ local.all_policy_statements      │                              ║
║                                                     └──────────────┬───────────────────┘                              ║
║                                                                    │                                                   ║
║                                                                    ▼                                                   ║
║                                                     aws_s3_bucket_policy.this[0]                                      ║
║                                                                    │                                                   ║
║                                                                    │                                                   ║
║           ┌────────────────────────────────────────────────────────┴────────────────────────────────────┐             ║
║           │                                                                                              │             ║
║           ▼                                                                                              ▼             ║
║  ┌─────────────────────────────────────────┐                                ┌─────────────────────────────────────┐   ║
║  │            BUCKET OUTPUTS               │                                │       ENCRYPTION OUTPUTS            │   ║
║  │  • bucket_id                            │                                │  • encryption_algorithm             │   ║
║  │  • bucket_arn                           │                                │  • kms_key_id                       │   ║
║  │  • bucket_domain_name                   │                                │                                     │   ║
║  │  • bucket_regional_domain_name          │                                └─────────────────────────────────────┘   ║
║  │  • bucket_hosted_zone_id                │                                                                          ║
║  │  • bucket_region                        │                                ┌─────────────────────────────────────┐   ║
║  │  • bucket_policy                        │                                │       OTHER OUTPUTS                 │   ║
║  │  • versioning_enabled                   │                                │  • versioning_enabled               │   ║
║  └─────────────────────────────────────────┘                                └─────────────────────────────────────┘   ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_s3_bucket` | 1 | Core S3 bucket resource |
| `aws_s3_bucket_public_access_block` | 1 | Block public access settings |
| `aws_s3_bucket_server_side_encryption_configuration` | 1 | Encryption configuration (SSE-S3 or SSE-KMS) |
| `aws_s3_bucket_versioning` | 1 | Versioning configuration |
| `aws_s3_bucket_request_payment_configuration` | 0 or 1 | Requester Pays (when `requester_pays_enabled` is true) |
| `aws_s3_bucket_cors_configuration` | 0 or 1 | CORS rules (when rules provided) |
| `aws_s3_bucket_lifecycle_configuration` | 0 or 1 | Lifecycle rules (when rules provided) |
| `aws_s3_bucket_policy` | 0 or 1 | Bucket policy (when templates or custom policy provided) |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | The name of the S3 bucket. Must be globally unique and follow AWS S3 naming rules. | `string` | n/a | yes |
| tags | A map of tags to assign to resources. Merged with default module tags. | `map(string)` | `{}` | no |

### Bucket Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| force_destroy_enabled | Whether to force destroy the bucket even if it contains objects. Use with caution. | `bool` | `false` | no |
| requester_pays_enabled | Whether the requesting account pays for requests and data transfer instead of the bucket owner. Anonymous requests and requests without the `x-amz-request-payer` header are refused. | `bool` | `false` | no |

### Encryption

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| kms_key_id | The AWS KMS key ID or ARN for SSE-KMS encryption. If not specified, SSE-S3 (AES256) is used. | `string` | `null` | no |
| bucket_key_enabled | Whether to enable S3 Bucket Keys for SSE-KMS (reduces KMS API costs). Only applicable when kms_key_id is provided. | `bool` | `true` | no |

### Versioning

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| versioning_enabled | Whether to enable versioning for the S3 bucket. | `bool` | `false` | no |

### CORS Rules

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cors_rules | List of CORS rule configurations for browser-based cross-origin access. | `list(object({...}))` | `[]` | no |

### Lifecycle Rules

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| lifecycle_rules | List of lifecycle rule configurations for the bucket. | `list(object({...}))` | `[]` | no |

### Bucket Policy

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| policy_templates | List of policy template names to apply. Available: `deny_insecure_transport`, `alb_access_logs`, `nlb_access_logs`, `vpc_flow_logs`, `cloudfront_oac_read`. | `list(string)` | `[]` | no |
| cloudfront_distribution_arns | CloudFront distribution ARNs allowed to read objects when `cloudfront_oac_read` is selected. | `list(string)` | `[]` | no |
| custom_policy | Custom bucket policy JSON document. If provided alongside policy_templates, policies will be merged. | `string` | `null` | no |

### Public Access Block

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| block_public_acls | Whether Amazon S3 should block public ACLs for this bucket. | `bool` | `true` | no |
| block_public_policy | Whether Amazon S3 should block public bucket policies for this bucket. | `bool` | `true` | no |
| ignore_public_acls | Whether Amazon S3 should ignore public ACLs for this bucket. | `bool` | `true` | no |
| restrict_public_buckets | Whether Amazon S3 should restrict public bucket policies for this bucket. | `bool` | `true` | no |

## Outputs

### S3 Bucket

| Name | Description |
|------|-------------|
| bucket_id | The name of the S3 bucket |
| bucket_arn | The ARN of the S3 bucket |
| bucket_domain_name | The bucket domain name (e.g., bucket-name.s3.amazonaws.com) |
| bucket_regional_domain_name | The bucket region-specific domain name (e.g., bucket-name.s3.us-east-1.amazonaws.com) |
| bucket_hosted_zone_id | The Route 53 Hosted Zone ID for this bucket's region (for alias records) |
| bucket_region | The AWS region this bucket resides in |

### Bucket Policy

| Name | Description |
|------|-------------|
| bucket_policy | The policy document attached to the bucket (null if no policy) |

### Versioning

| Name | Description |
|------|-------------|
| versioning_enabled | Whether versioning is enabled on the bucket |

### Encryption

| Name | Description |
|------|-------------|
| encryption_algorithm | The server-side encryption algorithm used (AES256 or aws:kms) |
| kms_key_id | The KMS key ID used for encryption (null if using SSE-S3) |

## Lifecycle Rules

The `lifecycle_rules` variable accepts a list of objects with the following structure:

| Field | Description | Type | Required |
|-------|-------------|------|----------|
| id | Unique identifier for the rule | `string` | yes |
| enabled | Whether the rule is enabled | `bool` | no |
| prefix | Object key prefix to filter objects | `string` | no |
| tags | Tags to filter objects | `map(string)` | no |
| expiration | Settings for expiring current objects | `object` | no |
| noncurrent_version_expiration | Settings for expiring noncurrent versions | `object` | no |
| transitions | List of transitions to different storage classes | `list(object)` | no |
| noncurrent_version_transitions | Transitions for noncurrent versions | `list(object)` | no |
| abort_incomplete_multipart_upload_days | Days after which incomplete multipart uploads are aborted | `number` | no |

## CORS Rules

The `cors_rules` variable accepts a list of objects with the following structure:

| Field | Description | Type | Required |
|-------|-------------|------|----------|
| id | Optional unique identifier for the rule | `string` | no |
| allowed_headers | Headers allowed in CORS requests | `list(string)` | no |
| allowed_methods | HTTP methods allowed in CORS requests. Valid values: `GET`, `PUT`, `HEAD`, `POST`, `DELETE` | `list(string)` | yes |
| allowed_origins | Origins allowed to make CORS requests | `list(string)` | yes |
| expose_headers | Response headers browsers may expose to client code | `list(string)` | no |
| max_age_seconds | Seconds browsers can cache preflight responses | `number` | no |

### Storage Classes for Transitions

Valid storage classes for transitions:
- `STANDARD_IA` - Standard-Infrequent Access
- `ONEZONE_IA` - One Zone-Infrequent Access
- `INTELLIGENT_TIERING` - Intelligent-Tiering
- `GLACIER` - Glacier Flexible Retrieval
- `GLACIER_IR` - Glacier Instant Retrieval
- `DEEP_ARCHIVE` - Glacier Deep Archive

## Policy Templates

The module includes pre-built bucket policy templates for common use cases:

| Template Name | Description |
|---------------|-------------|
| `deny_insecure_transport` | Denies requests that don't use HTTPS (enforces TLS) |
| `alb_access_logs` | Allows ALB to write access logs to the bucket |
| `nlb_access_logs` | Allows NLB to write access logs to the bucket |
| `vpc_flow_logs` | Allows VPC Flow Logs to write logs to the bucket |

Multiple templates can be combined, and they can also be used alongside a custom policy. All policies are merged into a single bucket policy.

## FAQ

### What encryption options are available?

This module supports two encryption options:

| Encryption Type | When to Use | Configuration |
|-----------------|-------------|---------------|
| **SSE-S3 (AES256)** | Default, simple setup, no key management needed | Don't specify `kms_key_id` |
| **SSE-KMS** | Compliance requirements, key rotation control, audit logging | Specify `kms_key_id` |

**SSE-S3 (Default):**
```hcl
module "s3" {
  source = "..."
  name   = "my-bucket"
  # SSE-S3 is used automatically when kms_key_id is not specified
}
```

**SSE-KMS with Bucket Keys (recommended for cost):**
```hcl
module "s3" {
  source             = "..."
  name               = "my-bucket"
  kms_key_id         = aws_kms_key.s3.arn
  bucket_key_enabled = true  # Default, reduces KMS API costs
}
```

### How should I configure lifecycle rules for cost optimization?

Lifecycle rules help manage storage costs by automatically transitioning objects to cheaper storage classes or expiring them.

**Recommended Strategy for Logs:**
```hcl
lifecycle_rules = [
  {
    id     = "logs-lifecycle"
    prefix = "logs/"
    transitions = [
      { days = 30,  storage_class = "STANDARD_IA" },     # Infrequent access
      { days = 90,  storage_class = "GLACIER" },         # Archive
      { days = 180, storage_class = "DEEP_ARCHIVE" }     # Long-term archive
    ]
    expiration = { days = 365 }
  }
]
```

**Recommended Strategy for Versioned Buckets:**
```hcl
lifecycle_rules = [
  {
    id = "version-cleanup"
    noncurrent_version_expiration = {
      noncurrent_days           = 30   # Delete old versions after 30 days
      newer_noncurrent_versions = 3    # Keep at least 3 versions
    }
    abort_incomplete_multipart_upload_days = 7
  }
]
```

**Storage Class Transition Minimums:**

| Transition | Minimum Days |
|------------|--------------|
| STANDARD to STANDARD_IA | 30 days |
| STANDARD to ONEZONE_IA | 30 days |
| STANDARD_IA to GLACIER | 30 days after IA |
| Any to DEEP_ARCHIVE | 90 days (or 180 from GLACIER) |

### What do the public access block settings do?

All four public access block settings are enabled by default for security:

| Setting | Purpose | Default |
|---------|---------|---------|
| `block_public_acls` | Blocks PUT calls with public ACLs | `true` |
| `block_public_policy` | Blocks PUT calls with public bucket policies | `true` |
| `ignore_public_acls` | Ignores all public ACLs on the bucket | `true` |
| `restrict_public_buckets` | Restricts access to bucket owners and AWS services | `true` |

**When to disable (with caution):**
- Static website hosting: May need to disable `block_public_policy` and `restrict_public_buckets`
- CloudFront OAI: Generally keep all enabled, use bucket policy for CloudFront access

```hcl
# Example: Static website (NOT recommended for sensitive data)
module "s3_website" {
  source = "..."
  name   = "my-website-bucket"

  block_public_acls       = true
  block_public_policy     = false  # Allow public policy for website
  ignore_public_acls      = true
  restrict_public_buckets = false  # Allow public access via policy
}
```

### How do I combine policy templates with custom policies?

Policy templates and custom policies are automatically merged:

```hcl
module "s3" {
  source = "..."
  name   = "my-bucket"

  # Use built-in templates
  policy_templates = ["deny_insecure_transport", "alb_access_logs"]

  # Add custom statements (will be merged)
  custom_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCrossAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::123456789012:root" }
        Action    = ["s3:GetObject", "s3:ListBucket"]
        Resource  = [
          "arn:aws:s3:::my-bucket",
          "arn:aws:s3:::my-bucket/*"
        ]
      }
    ]
  })
}
```

The final policy will contain all statements from both templates and custom policy.

### Should I enable versioning?

| Use Case | Recommendation |
|----------|----------------|
| Production data | Yes - enables recovery from accidental deletion |
| Compliance requirements | Yes - provides audit trail |
| Log buckets | Usually no - use lifecycle rules for retention |
| Temporary/cache data | No - unnecessary overhead |
| Terraform state | Yes - critical for state recovery |

**Important:** When versioning is enabled, deleted objects are not actually removed - they become "delete markers". Use lifecycle rules to manage noncurrent versions:

```hcl
module "s3" {
  source             = "..."
  name               = "my-bucket"
  versioning_enabled = true

  lifecycle_rules = [
    {
      id = "cleanup-versions"
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    }
  ]
}
```

## Security Considerations

- **Public Access Blocked**: All four public access block settings are enabled by default.
- **Encryption**: Server-side encryption is always enabled. Uses SSE-S3 (AES256) by default, or SSE-KMS when a KMS key is provided.
- **SSE-C Blocked**: Uploads encrypted with customer-provided keys are blocked to preserve the secure S3 bucket default.
- **HTTPS Enforcement**: Use the `deny_insecure_transport` policy template to enforce HTTPS-only access.
- **CloudFront OAC**: Use the `cloudfront_oac_read` policy template with distribution ARNs to keep buckets private behind CloudFront.
- **Bucket Keys**: When using SSE-KMS, S3 Bucket Keys are enabled by default to reduce KMS API costs.

## Notes

- Bucket names must be globally unique across all AWS accounts.
- Bucket names must be between 3-63 characters, contain only lowercase letters, numbers, hyphens, and periods.
- The `force_destroy_enabled` option should be used with caution in production environments.
- When using lifecycle rules with versioning, consider configuring `noncurrent_version_expiration` to manage storage costs.
- Policy templates automatically use data sources and module inputs to get the current account ID, region, ELB service account, and CloudFront distribution ARNs for proper policy configuration.
- The bucket policy resource depends on the public access block to ensure proper ordering during creation.
