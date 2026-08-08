# Ravion Modules

OpenTofu/Terraform module library for [Ravion](https://www.ravion.com/).

## Overview

This repository contains reusable infrastructure modules designed for enterprise-grade deployments. All modules follow OpenTofu/Terraform best practices and are optimized for use with Flightcontrol's module system.

### Compatibility

- **OpenTofu**: >= 1.10.0
- **Terraform**: >= 1.5.0

## Module Directory

| Category      | Module            | Description                                                            | Status  |
| ------------- | ----------------- | ---------------------------------------------------------------------- | ------- |
| `cache/`      | `elasticache`     | AWS ElastiCache clusters (Redis, Valkey, Memcached)                    | v1.0.0  |
| `cdn/`        | `cloudfront`      | AWS CloudFront distributions with origins, cache behaviors, and edge redirects (includes `rvn-cloudfront` module definition) | v1.0.0  |
| `compute/`    | `autoscaling`     | AWS Auto Scaling groups                                                | v1.0.0  |
| `compute/`    | `ec2_service`     | Supervised EC2 workloads with configurable rolling deploys, standalone or ECS-cluster ALB routing, target tuning, and deployment-scoped CloudWatch logs | v1.0.0  |
| `compute/`    | `ecs_cluster`     | AWS ECS clusters with Fargate/EC2 capacity providers and optional ALBs/NLBs | v1.0.0  |
| `compute/`    | `ecs_service`     | AWS ECS services with task definitions, task IAM policies, load balancing, and auto scaling | v1.0.0  |
| `compute/`    | `lambda`          | AWS Lambda functions                                                   | v1.0.0  |
| `database/`   | `aurora`          | AWS Aurora clusters (MySQL, PostgreSQL, Serverless v2, Global Database) (includes `rvn-aurora` module definition) | v1.1.0  |
| `database/`   | `dynamodb`        | AWS DynamoDB tables                                                    | v1.0.0  |
| `database/`   | `rds`             | AWS RDS instances                                                      | v1.1.0  |
| `hosting/`    | `static_site`     | Composite static site hosting (S3 + CloudFront + OAC, optional CloudFront Function / Lambda@Edge) | v1.0.0  |
| `kubernetes/` | `eks_cluster`     | AWS EKS clusters with OIDC, KMS-encrypted secrets, control plane logging, core add-ons, EBS CSI / Pod Identity Agent, LB Controller Pod Identity role, and access entries | v1.0.0  |
| `kubernetes/` | `eks_node_group`  | AWS EKS managed node groups (one per module) with IAM, optional launch template, taints, labels, and SPOT/ON_DEMAND capacity | v1.0.0  |
| `kubernetes/` | `eks_fargate_profile` | AWS EKS Fargate profiles (one per module) with pod execution role | v1.0.0  |
| `kubernetes/` | `eks_karpenter`   | Karpenter on AWS: controller Pod Identity role, node role + instance profile, EC2_LINUX access entry, SQS interruption queue, and EventBridge rules | v1.0.0  |
| `messaging/`  | `sns`             | AWS SNS topics and subscriptions                                       | Planned |
| `messaging/`  | `sqs`             | AWS SQS queues                                                         | Planned |
| `monitoring/` | `cloudwatch`      | AWS CloudWatch alarms and dashboards                                   | Planned |
| `networking/` | `alb`             | Standalone AWS Application Load Balancer with shared HTTP/HTTPS listeners | v1.0.0  |
| `networking/` | `eips`            | AWS Elastic IP pool with deterministic Name tags and `/32` CIDR outputs | v1.0.0  |
| `networking/` | `nlb`             | AWS Network Load Balancers                                             | v1.0.0  |
| `networking/` | `route53`         | AWS Route53 hosted zones and records                                   | v1.0.0  |
| `networking/` | `security-groups` | AWS Security Groups                                                    | v1.0.0  |
| `networking/` | `vpc`             | AWS VPC with adaptive public and private subnets                       | v1.0.0  |
| `security/`   | `acm_certificate` | AWS ACM public certificates with ordered domains, DNS validation, optional Route53, and optional wait | v1.0.0  |
| `security/`   | `iam`             | AWS IAM roles and policies                                             | v1.0.0  |
| `security/`   | `iam_policy`      | Reusable customer-managed AWS IAM policies                             | v1.0.0  |
| `security/`   | `kms`             | AWS KMS keys (symmetric or asymmetric: signing, encryption, MAC, key agreement) | v1.0.0  |
| `security/`   | `secrets-manager` | AWS Secrets Manager secrets                                            | Planned |
| `stack/`      | `terraform`       | Ravion Terraform/OpenTofu stack workflows with git triggers and managed state (includes `rvn-stack` module definition) | v1.2.3  |
| `storage/`    | `ebs`             | AWS EBS volumes                                                        | Planned |
| `storage/`    | `efs`             | AWS EFS file systems with mount targets, client/mount-target security groups, and optional access point | v1.0.0  |
| `storage/`    | `s3`              | AWS S3 buckets with encryption, SSE-C blocking, lifecycle rules, CORS, and bucket policies | v1.0.0  |

## Published Module Definitions

The table below is generated from the `release.version` in each `*-definition.yml` file and is kept in
sync by `node tools/ravion-modules/dist/src/cli.js readme` (enforced in CI, and refreshed on publish).

<!-- BEGIN GENERATED: module-definitions -->

| Definition | Name | Version | Module path |
| ---------- | ---- | ------- | ----------- |
| `rvn-acm-certificate` | ACM Certificate | v1.0.1 | `security/acm_certificate/` |
| `rvn-aurora` | Aurora Database | v1.1.1 | `database/aurora/` |
| `rvn-aws-alb` | AWS Application Load Balancer | v1.0.1 | `networking/alb/` |
| `rvn-aws-iam-policy` | AWS IAM Policy | v1.0.1 | `security/iam_policy/` |
| `rvn-aws-iam-role` | AWS IAM Role | v1.0.1 | `security/iam/` |
| `rvn-aws-network` | VPC Network | v1.0.1 | `networking/vpc/` |
| `rvn-aws-static` | Static Hosting | v1.0.1 | `hosting/static_site/` |
| `rvn-cloudfront` | CloudFront CDN | v1.1.0 | `cdn/cloudfront/` |
| `rvn-ec2-service` | EC2 Service | v1.0.1 | `compute/ec2_service/` |
| `rvn-ecs-cluster` | ECS Cluster | v1.0.1 | `compute/ecs_cluster/` |
| `rvn-ecs-nlb` | ECS Network Service | v1.0.1 | `compute/ecs_service/` |
| `rvn-ecs-web` | ECS Web Service | v1.0.1 | `compute/ecs_service/` |
| `rvn-ecs-worker` | ECS Worker | v1.0.1 | `compute/ecs_service/` |
| `rvn-efs` | EFS File System | v1.0.1 | `storage/efs/` |
| `rvn-elasticache` | ElastiCache | v1.0.1 | `cache/elasticache/` |
| `rvn-lambda` | Lambda Function | v1.0.1 | `compute/lambda/` |
| `rvn-rds` | RDS Database | v1.1.1 | `database/rds/` |
| `rvn-route53` | Route 53 DNS | v1.0.1 | `networking/route53/` |
| `rvn-s3` | S3 Bucket | v1.0.1 | `storage/s3/` |
| `rvn-stack` | Terraform Stack | v1.2.4 | `stack/terraform/` |

<!-- END GENERATED: module-definitions -->

## Usage

Reference modules using Git URLs with version pinning:

```hcl
module "sqs_queue" {
  source = "git::https://github.com/ravionhq/modules.git//messaging/sqs?ref=v1.0.0"

  # Module inputs
  name = "my-queue"
  # ...
}
```

### Version Pinning

Always pin to a specific version using Git tags:

```hcl
# Recommended: Pin to exact version
source = "git::https://github.com/ravionhq/modules.git//messaging/sqs?ref=v1.0.0"

# Alternative: Pin to major version branch (if available)
source = "git::https://github.com/ravionhq/modules.git//messaging/sqs?ref=v1"
```

## Module Standards

Each module in this repository follows a consistent structure:

```
<category>/<module-name>/
├── main.tf          # Primary resource definitions
├── variables.tf     # Input variables with descriptions and validation
├── outputs.tf       # Output values with descriptions
├── versions.tf      # Provider and OpenTofu version constraints
└── README.md        # Module documentation with usage examples
```

### Requirements

- All variables must have `description` and `type`
- All variables should have `validation` blocks where applicable
- All outputs must have `description`
- Resources must follow consistent naming conventions
- Security best practices must be followed (no hardcoded secrets, least privilege IAM)

## Contributing

## Module Definitions

Flightcontrol/Ravion module definitions are authored in this repository beside the Terraform
module they publish. Each definition source file is named `<definition.type>-definition.yml` and
lives in an existing module directory, for example `networking/vpc/rvn-aws-network-definition.yml`.

The definition file has three top-level sections:

```yaml
definition:
  type: ravion-aws-vpc
  name: AWS VPC
  description: AWS VPC and subnets

release:
  version: 1.2.0
  description: |
    Add VPC flow log options and support S3 flow log destinations.

module:
  inputs:
    - id: region
      type: string
      label: AWS Region
      required: true
  stack:
    type: opentofu
    source:
      repo: https://github.com/ravionhq/modules
      ref: $local.module_tag
      base_path: networking/vpc
```

`definition` contains repo-owned module identity and display metadata. `release` contains the
next module version to publish and the curated changelog description for that version. `module`
contains the canonical Flightcontrol module config that is compiled, validated, and published.

### Authoring Rules

- Create module definitions only as colocated `<definition.type>-definition.yml` files beside existing Terraform modules.
- Keep `definition.type` stable once published. It is the module identity used for versioning.
- Set `release.version` to a valid semantic version whenever a new module version should publish.
- Write `release.description` as the human-readable changelog entry for that published version.
- Keep Ravion runtime templates such as `<< module.given_id >>` inside `module`; they pass through unchanged.
- Use `$local.module_tag` only where the compiled definition should reference this module release tag.

### Composition Directives

Definitions support explicit composition at the exact insertion point. Shared fragments should live
under `partials/` when reuse is useful, but use the directive where the content should appear rather
than relying on inheritance.

| Directive | Where it is used | Behavior |
| --------- | ---------------- | -------- |
| `$include` in an array item | `inputs`, arrays, ordered blocks | Splices the included array or single item into that position. |
| `$include` as a map value | Object properties or config values | Replaces that value with the included file content. |
| `$merge` in a map | Stack, deploy, settings, or object maps | Merges one or more maps into the current map. Later keys override earlier keys. |
| `$template` in an array item or map value | Parameterized repeated fragments | Loads a fragment and renders it with values from `with`. |
| `$local.module_tag` in a scalar | Source refs and docs | Resolves to `<definition.type>@<release.version>`. |

Directive paths are resolved relative to the file that contains the directive. Cycles fail during
compile, and compiled output must not contain repo-only metadata, composition directives, or
unresolved `$local.*` tokens.

Example directive usage:

```yaml
module:
  inputs:
    - $include: ../../partials/inputs/name.yml
    - id: networking
      type: section
      label: Networking
    - $template: ../../partials/templates/ref-input.yml
      with:
        id: vpc
        type: stack
        label: VPC

  stack:
    $merge:
      - ../../partials/stack/pipelines.yml
      - ravion_state_backend_workspace: "<< module.given_id >>"
    type: opentofu
    source:
      repo: https://github.com/ravionhq/modules
      ref: $local.module_tag
      base_path: networking/vpc
```

### Validation And Status

The module definition tooling lives in `tools/ravion-modules`.

```bash
cd tools/ravion-modules
npm install
npm run typecheck
npm test
node dist/src/cli.js validate ../../networking/vpc/rvn-aws-network-definition.yml
node dist/src/cli.js compile
node dist/src/cli.js status
```

`validate` checks an authored definition, compiles it, and validates the canonical module config.
`compile` compiles all colocated definitions and verifies local release metadata. `status` reports
each local release version and can compare it with remote inventory when run with
`--inventory <inventory.json>`.

### Publishing

Publishing is handled after merge on `main`. The publish workflow compiles all definitions, compares
local releases with existing Ravion module versions, creates any missing module-scoped tags, and
publishes missing versions through the Ravion API.

Pull requests run the same publish comparison in dry-run mode and post a PR comment with the
planned creates, patches, skips, and config diffs. The dry run uses `https://api.ravion.com` and
requires `RAVION_API_TOKEN`; when the token is missing, CI fails with an explicit credential error.
Pull requests also run `node dist/src/cli.js version-dry-run`, which validates each
pending module version's config through the Ravion API's module version dry run without creating
anything. It skips already-published versions and definitions that do not exist remotely yet, and
reports every failing definition at once.

Manual dry runs use the same commands:

```bash
cd tools/ravion-modules
node dist/src/cli.js tags --api
node dist/src/cli.js publish
node dist/src/cli.js version-dry-run
```

Mutation commands are explicit:

```bash
node dist/src/cli.js tags --api --create
node dist/src/cli.js publish --apply
```

`publish` creates missing definitions, patches changed definition metadata, creates missing module
versions, and skips already-published identical versions. It fails if the same `release.version`
already exists remotely with different compiled config.

Local development publishes can target a local API server and apply by default:

```bash
cd tools/ravion-modules
node dist/src/cli.js publish ../../networking/vpc/rvn-aws-network-definition.yml --local-dev
```

From the repository root, use the Makefile shortcuts:

```bash
make publish-local-dev MODULE=rvn-aws-network
make publish-local-dev MODULE=rvn-aws-network DRY_RUN=1
make publish-local-dev MODULE=rvn-aws-network SOURCE_REF=my-pushed-branch
```

The Makefile publish command automatically loads `.env.local` for that command when the file exists.
Use standard dotenv syntax:

```bash
RAVION_API_URL=http://localhost:8080
RAVION_API_TOKEN=dev-token
```

To load `.env.local` into the current terminal session, run the helper for your shell:

```bash
eval "$(make env-local-sh)"
```

```fish
eval (make env-local-fish)
```

`--local-dev` defaults to `http://localhost:8080`, or `RAVION_API_URL` when set. It always publishes
a numeric prerelease suffix from the authored `release.version`, for example `0.1.0-1`, `0.1.0-2`,
and so on. The module's GitHub source ref uses the current branch when that branch exists on
`origin`; otherwise it uses `main`. Set `SOURCE_REF` or `RAVION_LOCAL_DEV_SOURCE_REF` to override
that source ref. Use `--dry-run` with `--local-dev` to dry-run without API mutations.

### Module Release Tags

Published definitions use module-scoped annotated Git tags as source refs, for example
`ravion-aws-vpc@1.2.0`. Tags are created only after merge because pre-merge commit SHAs are not the
stable commits that will exist on `main`. Branch refs are mutable, so they are not suitable for
published module source pins.

Release tags are immutable. If a published module version is wrong, publish a new patch version
instead of moving or replacing the existing tag.

### Adding a New Module

1. Create a new directory following the `<category>/<module-name>` structure
2. Include all required files (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`)
3. Ensure all variables and outputs have descriptions
4. Add validation rules for variables where applicable
5. Include usage examples in the module's README
6. **Update this README's Module Directory table**
7. Run `tofu fmt` and `tofu validate` before committing

### Versioning

This repository follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes (removed variables, renamed resources, changed defaults that affect behavior)
- **MINOR**: New features, new modules, new optional variables
- **PATCH**: Bug fixes, documentation updates

## Testing

This repository uses [Terratest](https://terratest.gruntwork.io/) for integration testing of infrastructure modules. Tests deploy real AWS resources to validate module behavior.

### Prerequisites

Set the following environment variables before running tests:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"  # Optional, defaults to us-east-1
```

### Running Tests

```bash
# Navigate to the test directory
cd test

# Run all tests
go test -v -timeout 60m ./...

# Run a specific test
go test -v -timeout 30m -run TestVpcBasic ./...

# Run tests with parallel limit (recommended for cost control)
go test -v -timeout 60m -parallel 2 ./...
```

### Cost Considerations

Integration tests create real AWS resources which incur costs. Tests clean up resources automatically via `terraform destroy`, but failed tests may leave orphaned resources. Monitor your AWS account for any resources tagged with `Environment=terratest`.

For detailed information about the test architecture and adding new tests, see [TERRATEST_PLAN.md](TERRATEST_PLAN.md).

## License

This project is licensed under the **Functional Source License, Version 1.1, MIT Future License (FSL-1.1-MIT)**.

See the [LICENSE](LICENSE) file for the full license text.

This means:

- You can use, copy, modify, create derivative works, publicly perform, publicly display, and redistribute this code for any permitted purpose
- You may not use this code for a competing commercial product or service before the future license date
- Each software version becomes available under the MIT License on the second anniversary of its release
- You must retain copyright notices and include the license terms when redistributing copies, modifications, or derivatives
- The software is provided "as is", without warranty
