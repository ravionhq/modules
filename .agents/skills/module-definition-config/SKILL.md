---
name: module-definition-config
description: Create, analyze, and update Ravion module definition config in colocated *-definition.yml files for inputs, OpenTofu stack pipelines, build/deploy wiring, UI links, CloudWatch metrics, and hidden-input nil safety. Use when working on module definition config for VPC/network, ECS cluster, ECS web/service, static site, ACM, or similar Ravion infrastructure modules; first inspect similar existing repo definitions and do not use README content as source material.
---

# Module Definition Config

Focus on executable config shape in repo-authored module definitions: `module.inputs`, `module.stack`, `module.build`, `module.deploy`, and `module.ui`. Do not infer behavior from README prose.

## Repository Model

Module definitions are source-controlled beside Terraform modules as `<definition.type>-definition.yml` files. The top-level `definition` block owns catalog metadata, `release` owns version metadata, and `module` contains the canonical Flightcontrol module config after compilation.

Do not create or update module definitions directly with executor or Ravion Local API calls. Author files in this repo, validate with `tools/ravion-modules`, and use the local publishing tool when a local API publish is needed.

Within `module`, keep executable config before documentation in this order when present: `inputs`, `stack`, `build`, `deploy`, `ui`, `readme`. Always place `readme` last.

## Sourcing Reference Definitions

Find active reference definitions by filename instead of relying on a fixed list:

```text
**/*-definition.yml
```

Exclude test fixtures and generated files, especially paths under `tools/ravion-modules/test/fixtures`.

When a definition uses or mentions a module type, source that reference module by filename:

```text
**/<definition.type>-definition.yml
```

For `$ref:<module-type>` inputs, remove the `$ref:` prefix and inspect the active file matching `**/<module-type>-definition.yml`. Use that file to verify mapped inputs, stack outputs, inherited account/region behavior, and any dependency-specific conventions.

## Similar Definition Review

Before authoring or reviewing config, search for active `*-definition.yml` files outside `tools/ravion-modules/test/fixtures` and inspect the closest examples. Choose examples by category, AWS service family, dependency model, runtime/deploy model, stack type, and UI complexity. If a dependency is expressed as `$ref:<module-type>`, inspect `**/<module-type>-definition.yml` before designing or reviewing the dependent inputs.

Use examples to match repository conventions for:

- Input section order, labels, descriptions, defaults, `required`, `values`, nested `item_inputs`, and `show_when` style.
- `$ref:*` dependency inputs and inherited account, region, VPC, subnet, listener, certificate, cluster, and capacity fields.
- Shared partial includes, especially Terraform settings and common stack pipeline shape.
- `module.stack.pipelines.defaults.input` ordering, source fields, tag maps, and Terraform variable expression style.
- Build/deploy split for deployable workloads and disabled build modes.
- UI link and CloudWatch metric structure.
- Overall `module` field order: `inputs`, `stack`, `build`, `deploy`, `ui`, then `readme` last.
- Release description style for publishable config changes.

Do not copy an example blindly. Reconcile it with the authoritative schema and the target Terraform module behavior. If the closest examples conflict with the schema, follow the schema and preserve only the compatible local style.

## Workflow

1. Inspect the target `<definition.type>-definition.yml`, nearby definitions, active similar definitions, partials, and Terraform source before changing config.
2. Read the full authoritative module config schema from `https://api.ravion.com/module-definitions/schema.md` before authoring or reviewing config shape. Use it to verify exact field names, required fields, allowed discriminators, template expression rules, and nested build/deploy/UI schemas.
3. Ignore `module.readme` during config analysis; remove it from summaries and comparisons unless the task is specifically README work.
4. Compare the closest existing definitions against the target Terraform module so new config follows repo style while still reflecting the target module's real variables and behavior.
5. Compare Terraform module variables against `module.inputs`; expose most Terraform variables as module inputs unless they are intentionally fixed, internal, derived, or too rare for the normal UI.
6. Check ref inputs first, because `$ref:*` inputs supply inherited values such as AWS account, region, VPC IDs, subnet IDs, cluster ARNs, listeners, and capacity provider names.
7. Verify `module.stack.pipelines.defaults.input.terraform_variables` maps every module-facing input to the source module variable intentionally.
8. Verify dynamic `values` expressions use available context and ref-derived inputs.
9. Verify `show_when` hides every field that only applies when another toggle, mode, or enum value is enabled.
10. Treat every value-producing input with `show_when` as nullable. Audit every runtime template use of that input and make arithmetic, conversion, concatenation, indexing, collection, and nested-member operations nil-safe.
11. Use `advanced_terraform_variables` and `"...overrides"` only for intentional escape hatches.
12. Update `release.description` when the authored version represents a publishable user-facing or internal change.

## Schema Reference

The full config schema is the source of truth for accepted module config shape:

```text
https://api.ravion.com/module-definitions/schema.md
```

Read this schema during config work, especially when adding or changing input property types, `show_when`, dynamic values, `module.stack`, `module.build`, `module.deploy`, or `module.ui`. Do not rely only on nearby examples when the schema provides stricter required fields or discriminator-specific shapes.

## Versioning

Each definition owns its pending release metadata directly:

```yaml
release:
  version: 0.1.0
  description: Add configurable access logs.
```

Write `release.description` as concise, user-facing release-note copy: describe the fix or capability from the user's point of view, never the implementation mechanism. Good: `Prevent applies from failing with CloudFront in-use errors when disabling a managed feature.` Bad: `Add create_before_destroy to order resource deletion.`

Use semantic versioning for released module definitions. For local development publishes, do not bump `release.version` just to publish a new local copy; the local publish tooling automatically appends the next numeric prerelease suffix to the authored version, such as `0.2.1-1`, `0.2.1-2`, and so on.

## Input Patterns

Use `section` entries to group related fields. IDs should be stable snake_case and should match Terraform variable names when practical. Form labels and section labels must use sentence case, except for service names and acronyms.

Keep input validation `patterns[].message` text concise and direct. Avoid filler instructions such as "Use ..." when the constraint can stand alone, for example `1-40 lowercase letters, numbers, and hyphens. Start and end with a letter or number.` For invalid-value messages that name the field type, start with `Invalid`, for example `Invalid RDS master username. Start with a letter. Letters, numbers, and underscores only.` For reserved-name validation, use `Pick a different name, this is reserved by AWS.` Avoid lookahead/lookbehind in module-definition regex patterns because backend validation may reject them.

For OpenTofu/Terraform-backed modules, put Terraform runner and escape-hatch inputs in a dedicated section included from `partials/inputs/terraform-settings.yml` when possible. This section should include inputs such as `execution_environment_id`, `opentofu_version` or other tool-version overrides, `advanced_terraform_variables`, and `ravion_state_backend_workspace`. Do not place `execution_environment_id` under the AWS account/region section, and do not leave `advanced_terraform_variables` in a generic advanced section.

Default to exposing Terraform variables as module inputs. The module-definition UI should make normal Terraform module capabilities available without requiring users to edit escape-hatch maps.

Expose a Terraform variable when:

- It changes common user-facing behavior, cost, networking, security, observability, sizing, routing, scaling, naming, or tagging.
- Different environments or applications are likely to choose different values.
- It has a safe default but users can reasonably override it.
- It corresponds to cloud resource configuration that users would expect to control from Ravion.

Do not expose a Terraform variable when:

- It is internal plumbing derived from refs, stack outputs, build/deploy config, project/environment/module context, or standard tags.
- It should be hard-coded to preserve Ravion behavior or avoid lifecycle conflicts.
- It is extremely rare, dangerous, implementation-specific, or better handled through an advanced override map.
- It duplicates a higher-level input that already captures the product decision.

Example: for ECS services, hard-code or derive initial Terraform `desired_count` when deploy/autoscaling owns runtime scale. Do not expose it as a normal input unless the module deliberately lets Terraform control steady-state desired count.

Common dynamic value sources:

- `$values:ravion/aws_accounts` for direct AWS account selection.
- `$values:aws/regions` for region selection.
- `$values:ravion/execution_environments` for Terraform runner overrides.
- `$values:opentofu/versions` for OpenTofu version overrides.
- `$values:aws/ec2/instances?awsAccountId=<<module.input.aws_account_id>>&region=<<module.input.aws_region>>` for EC2 sizes.
- `$values:aws/fargate/sizes?region=<<module.input.aws_region>>&cpuArchitecture=<<module.input.cpu_architecture>>&operatingSystem=linux&capacityProvider=<<module.input.capacity_provider>>` for Fargate size compounds with `fields: [vcpu, memory_gb]`.

Dependency patterns:

- Root infrastructure modules expose direct `aws_account_id` and `aws_region` inputs.
- Dependent modules should prefer a `$ref:<module-type>` input over asking for values already produced by the referenced module.
- Source the referenced module with `**/<module-type>-definition.yml` before mapping inherited inputs or stack outputs.
- Give every free-form mapped input with a `ref.*` default an explicit, realistic `placeholder` for "enter your own values" mode. Never let the ref expression itself appear as the placeholder. Use a syntactically representative value such as a complete ARN, resource ID, endpoint URL, cluster name, or subnet ID.

Use `collapsible: true` for advanced settings. Never make an input collapsible when it is required and has no guaranteed non-nil default in every mode where it is visible. A collapsed required field without a default hides unfinished configuration and prevents users from seeing what they must provide. Keep such fields expanded. For mapped inputs, a `default` derived from `ref.*` does not count as a guaranteed default in "enter your own values" mode because no reference exists there.

Use `show_when` for build-type, EC2-only, load-balancer-only, autoscaling-only, replica-only, alarm-only, custom-credentials-only, existing-resource-only, and engine-specific fields.

## Input Immutability

Mark an input `immutable: true` only when changing it after creation would change foundational resource identity, move the stack to a different AWS target, or orphan/duplicate state-managed resources. Do not infer immutability from Terraform replacement alone; many replacement-prone operational controls are intentionally editable. Do not mark `advanced_terraform_variables` immutable; it intentionally remains a mutable escape hatch even though it can override protected Terraform variables.

Always mark these shared target/state inputs immutable when they are direct inputs or ref fallback inputs:

- `aws_account_id`
- `aws_region`
- `ravion_state_backend_workspace`
- Ref-derived infrastructure identity fields such as `vpc_id`, subnet IDs, cluster ARNs, listener ARNs, load balancer security group IDs, and capacity provider names.

Never mark `execution_environment_id` immutable. Execution environment selection is runner configuration, not infrastructure identity, and must remain editable.

Common module-specific immutable fields:

- Network/VPC modules: `name` and `vpc_cidr`.
- Certificate modules: certificate domain fields, SANs, Route53 validation-record creation toggle, and validation hosted zone ID.
- IAM role modules: role name/path, instance-profile creation toggle, instance-profile name, and instance-profile path.
- Static hosting modules: bucket/resource name.
- ECS cluster modules: selected network ref and cluster/resource name.
- ECS service modules: selected cluster ref and mapped fallback fields, service name, and container port when it feeds target group identity.

Keep operational and product-level controls mutable even when they can create/delete supporting resources, cause downtime, trigger a rollout, or replace lower-level resources. Examples that should generally remain mutable include execution environments, VPC NAT gateway settings and supplied NAT EIPs, VPC peering maps, VPC Flow Logs, CloudFront aliases, CloudFront ACM certificate ARN, static default version seed, access logging, ECS cluster EC2 capacity settings, ECS cluster load balancer toggles and NLB Elastic IP settings, ECS service public/private routing selection, ECS service build type, generated-vs-existing ECS IAM role override ARNs, health checks, autoscaling thresholds, cache headers, price class, IAM trust/policy documents, tags, descriptions, log retention, CPU/memory sizing, and deployment rollout settings.

## Field Visibility Rules

Default to hiding conditional fields. If a field is irrelevant, ignored, confusing, or invalid unless another input has a specific value, give it a `show_when` condition tied to that controlling input.

Common patterns:

- Feature toggle children: fields like read replica count, alarm thresholds, access log buckets, scheduled scaling details, or monitoring role settings should only show when their parent toggle is enabled.
- Mutually exclusive resource modes: existing resource IDs should show only when `*_creation_enabled` is false; fields used to create/manage the resource should show only when `*_creation_enabled` is true.
- Enum-specific settings: fields for SQL Server, Oracle, EC2, Fargate, gp3, io1/io2, public load balancers, private load balancers, or a specific build type should only show for matching enum values.
- Credential alternatives: manual password/secret fields should show only when automatic credential management is disabled; generated-secret KMS fields should show only when managed secrets are enabled.
- Observability details: alarm thresholds/actions/periods should show only when alarms are enabled; enhanced-monitoring role fields should show only when monitoring interval is non-zero; Performance Insights retention/KMS fields should show only when Performance Insights is enabled.
- Nested advanced configuration: parameter lists should show only when parameter group creation is enabled; option lists should show only when option group creation is enabled.

Use simple supported `show_when` forms:

```yaml
show_when:
  read_replica_creation_enabled: true
```

```yaml
show_when:
  security_group_creation_enabled: false
```

```yaml
show_when:
  monitoring_interval:
    not: 0
```

```yaml
show_when:
  engine:
    - sqlserver-ee
    - sqlserver-se
    - sqlserver-ex
    - sqlserver-web
```

Do not rely on `collapsible: true` as a substitute for `show_when`. Collapsible fields are still visible and should be reserved for valid-but-advanced settings, not fields that do not apply.

When a Terraform variable has a safe default that should always be used, omit the input and omit the generated Terraform variable instead of exposing a redundant form field. Example: if a database module defaults encryption at rest to true and Ravion should not encourage disabling it, do not expose `storage_encrypted`; let Terraform apply its default and use `advanced_terraform_variables` only for exceptional overrides.

## Hidden Input Nil Safety

Inputs hidden by `show_when` resolve to `nil`, even when the input definition has a non-nil `default`. This clearing is intentional. Never assume a hidden input retains its form default, and never work around the behavior by removing `show_when` or changing hidden-input normalization.

For every value-producing input with `show_when`, find every reference to `module.input.<id>` across `stack`, `build`, `deploy`, `ui`, included partials, and dynamic value templates. Apply the same audit to `item_inputs` referenced as `#.<id>` inside `map` or `filter` expressions.

Operations that require an explicit guard or fallback include:

- Arithmetic: `+`, `-`, `*`, `/`, `%`.
- Numeric and string conversion: `int(...)`, `float(...)`, and `string(...)` when the argument may be nil.
- String concatenation involving a hidden value.
- Collection operations that require a concrete array or map, including `concat(...)`, indexing, and iteration.
- Nested member access followed by any unsafe operation, such as `module.input.size.vcpu * 1024`.

Use one of these patterns:

- Guard the operation with an explicit `!= nil` or `!= null` check.
- Put the operation exclusively inside a short-circuited ternary branch controlled by the same mode or feature toggle as `show_when`.
- Coalesce arrays to `[]`, maps to `{}`, and optional strings to the semantically correct value before an operation.
- When converting a UI unit into a Terraform unit, fall back to the exact Terraform variable default from `variables.tf`, not merely the input's UI default.

Unsafe and safe threshold conversion:

```yaml
# Unsafe: threshold_gib becomes nil when alarms are disabled.
threshold_bytes: << int(module.input.threshold_gib * 1073741824) >>

# Safe: preserve the Terraform default when the form field is hidden.
threshold_bytes: '<< module.input.threshold_gib != nil ? int(module.input.threshold_gib * 1073741824) : 5368709120 >>'
```

Quote YAML template scalars containing ternary `:` characters. Do not rely on the YAML parser accepting an unquoted ternary expression.

Current template runtime guarantees make `nil` falsey, short-circuit boolean operators, resolve missing member access to nil, and define `len(nil)` as `0`. These behaviors make truthiness checks and `len(hidden_list) > 0` safe, but they do not make arithmetic or conversions on nil safe.

For a nil-safety bug fix, add a regression test in `tools/ravion-modules/test/compiler.test.ts` that compiles the real definition and asserts the guarded expression and exact Terraform fallback. Run the test before the fix to capture the unsafe expression, then after the fix and again as part of the full module-tool suite.

## Stack Pattern

For OpenTofu-backed modules, prefer the repository's shared partials when they fit. The compiled stack should preserve this shape:

```yaml
stack:
  type: opentofu
  pipelines:
    defaults:
      variant: standard
      input:
        repo: https://github.com/ravionhq/modules
        branch: main
        ref: $local.module_tag
        base_path: <module source path>
        stack_id: <<stack.id>>
        tool: opentofu
        tool_version: <<defaults.opentofu_version >>
        aws_account_id: << module.input.execution_environment_id ? null : module.input.aws_account_id >>
        aws_region: << module.input.execution_environment_id ? null : module.input.aws_region >>
        execution_environment_id: << module.input.execution_environment_id >>
        terraform_variables: {}
```

Use `$local.module_tag` in source refs that should resolve to `<definition.type>@<release.version>` at compile time. Use `<< module.input.ravion_state_backend_workspace || project.given_id + "-" + environment.given_id + "-" + module.given_id + "-" + stack.id>>` when workspace override is exposed.

Always include standard tags unless there is a specific reason not to: `Owner`, `ProjectGivenId`, `EnvironmentGivenId`, `ModuleGivenId`, `ModuleId`, plus `"...overrides": << module.input.tags >>`.

## ECS Web Pattern

For ECS service modules, keep infrastructure provisioning and release deployment separate:

- `module.stack` creates service scaffolding, ECR repository, IAM roles, target group/rules, log group, and autoscaling resources.
- `module.build.type` evaluates to `image` only for `railpack` and `dockerfile`; it is `disabled` for `public_image` and `disabled` build modes.
- `module.build.destinations` pushes to the service ECR repository with run-specific and build-type tags.
- `module.deploy.type: aws:ecs` owns ECS task-definition rendering and service update.
- `module.deploy.inputs.deploy_image` means digest for built images, tag for public images, and full image URI for disabled builds.
- Deployment concurrency should collapse stale queued deploys with `queue_size: 1` and `queue_overflow: oldest`.

When mapping task sizing, use Fargate compound values for Fargate providers and convert EC2 string inputs from vCPU/GB to CPU units/MiB in expressions.

## Validation And Local Publish

After changes, run the smallest useful validation first:

```bash
make modules-tools-build
node tools/ravion-modules/dist/src/cli.js validate <path-to-definition.yml>
node tools/ravion-modules/dist/src/cli.js compile <path-to-definition.yml>
```

For cross-definition release status checks, run:

```bash
node tools/ravion-modules/dist/src/cli.js compile
node tools/ravion-modules/dist/src/cli.js status
```

For local development publishes, use the Makefile target or direct CLI with `--local-dev`:

```bash
make publish-local-dev MODULE=<definition.type> DRY_RUN=1
make publish-local-dev MODULE=<definition.type>
```

```bash
node tools/ravion-modules/dist/src/cli.js publish <path-to-definition.yml> --local-dev --dry-run
node tools/ravion-modules/dist/src/cli.js publish <path-to-definition.yml> --local-dev
```

The local publish path targets `RAVION_API_URL` or `http://localhost:8080` by default and does not require executor. The Makefile loads `.env.local` for publish commands when present. Use `SOURCE_REF=<branch-or-ref>` or `RAVION_LOCAL_DEV_SOURCE_REF=<branch-or-ref>` when needed.

## Review Checklist

- No analysis or instructions depend on `module.readme`.
- `module` fields are ordered as `inputs`, `stack`, `build`, `deploy`, `ui`, `readme`, with `readme` last when present.
- Similar active repo definitions were inspected, and any divergence from them is intentional because of schema or target Terraform behavior.
- Every non-section input is consumed or intentionally provided for ref/dynamic-values wiring.
- Most user-relevant Terraform variables are exposed as inputs; omissions are deliberate and explainable.
- Every `module.input.*` reference is backed by a direct input or ref-derived field.
- Every free-form mapped input with a ref-derived default has a realistic manual-entry placeholder rather than exposing the ref expression.
- No required input is collapsible unless it has a guaranteed non-nil default in every visible mode; ref-derived mapped-input defaults are treated as absent in manual-entry mode.
- Required inputs hidden by `show_when` are only required when visible.
- Every dependent input has `show_when`; no replica-only, alarm-only, engine-only, existing-resource-only, or disabled-default field is visible unconditionally.
- Every value-producing input hidden by `show_when` is treated as nullable in all runtime templates, including included partials and nested `#.<id>` expressions.
- Arithmetic, conversions, concatenation, indexing, iteration, and nested-member operations on potentially hidden values have an explicit nil guard, a controller-matched short-circuited branch, or a type-correct fallback.
- Unit conversions use the exact Terraform default as their hidden-input fallback and have compiler regression coverage.
- Fields intentionally omitted to preserve safe Terraform defaults are not also emitted in `terraform_variables`.
- Destructive identity, target, state, and core topology inputs are marked `immutable: true`; `advanced_terraform_variables`, `execution_environment_id`, and observability/logging toggles remain mutable.
- `aws_account_id` and `aws_region` are nulled when an execution environment is selected.
- Source fields use the intended repo, base path, and `$local.module_tag` or explicit source ref.
- UI metrics use stable CloudWatch namespace, metric name, dimensions, account, and region expressions.
- ECS deploy task definition and stack variables agree on CPU, memory, platform, launch type, subnets, load balancer, and port.
- The definition validates and local publish, if requested, uses `tools/ravion-modules` or `make publish-local-dev`, not executor.
