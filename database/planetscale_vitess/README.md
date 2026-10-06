# PlanetScale MySQL

Managed PlanetScale MySQL with application credentials, safe migrations, and in-place cluster resizing.

## Overview

This OpenTofu root stack owns one PlanetScale Vitess database, its `main` branch,
the automatically-created default keyspace, and an application password. It uses
the released official `planetscale/planetscale` provider. No provider fork,
Speakeasy account, extra keyspace, or PlanetScale-specific pipeline is required.
PlanetScale resources do not support AWS-style tags, so this stack has no tags
input or AWS provider.

Defaults are PS-10, safe migrations enabled, deletion protection enabled, and a
non-expiring `readwriter` application credential. PlanetScale's built-in backups
and default VTGate configuration remain in effect. Additional keyspaces,
replicas, passwords, VTGate settings, and backup policies are optional.

## Deployment lifecycle

Each deployment uses one ordinary plan/approve/apply through Ravion's standard
Terraform change pipeline:

1. **First deployment:** create the branch at the selected cluster size. PlanetScale
   creates its default keyspace automatically. Create the application credentials
   and other configured resources. There is no import during this first plan.
2. **Second deployment:** automatically adopt that existing default keyspace into
   Terraform state. The same plan/apply can also change its size and extra replicas.
3. **Later deployments:** resize and reconcile the already-managed keyspace normally.

An import records an existing keyspace in Terraform state; it does not copy data,
create another keyspace, or provision another cluster. The branch's creation-time
`cluster_size` is ignored on updates because changing it through the branch
resource would replace the branch. The keyspace resource handles safe resizing.

Ravion determines the lifecycle from the previous successful deployment's
`branch_id` output and passes the internal `manage_default_keyspace` Terraform
variable automatically. Users do not set this switch in the module form. The
raw Terraform variable defaults to true to preserve existing callers' managed
keyspaces; Ravion explicitly passes false only for a new deployment.
Extra replicas are **first applied on the second deployment**, even when entered
before the first deployment. Deploy again if they are needed immediately afterward.

The existing keyspace lookup uses the immutable database/branch identity, so
changing safe migrations, deletion protection, or VTGate settings in the same
plan does not defer the lookup and break the import. A moved block preserves
previous versions' keyspace state address without recreation.

**Use this directory as a root stack**, not a nested Terraform module: its import
block and Ravion backend belong at the root. Keep the same workspace for every
run. Do not override `manage_default_keyspace` back to false after adoption;
that would remove its resource from the configuration and plan its deletion.

## Ravion setup

1. Add and validate a PlanetScale connection in **Settings → Integrations**.
   Enter the organization and bootstrap service token there once.
2. Add **PlanetScale MySQL** (`rvn-planetscale-vitess`). Select that active
   integration, database region, cluster size, and Terraform execution environment.
   **There is no provisioning pipeline ID to enter.** The normal change and destroy
   pipeline defaults are used.
3. Deploy and connect the application using the sensitive stack outputs.
4. On the next deployment, the module automatically adopts the existing keyspace.
   Changing the cluster size at that point imports and resizes it in the same apply.

The integration supplies the organization. The execution environment controls
where the runner executes, not the database's location. Region and size dropdowns
are scoped to the selected integration's PlanetScale organization and region.
Both network-storage and Metal sizes are listed. Metal disk capacity is part of
the full SKU; there is no separate disk setting.

The standard pipeline versions must accept `integrations` and `timeout` and
forward them to each Terraform step. Restarting Ravion does not update previously
published pipeline versions. The old `pipelines/change.yml` file is a legacy
workflow, not required by this module definition.

Every plan/apply/destroy step receives a separate short-lived child token. The
bootstrap token stays in the credentials broker. Ravion supplies the organization
through `TF_VAR_organization`. Each step has a 2700-second (45-minute) timeout so
expiry covers runner startup and execution. Rotation can replace credentials
without changing the selected integration.

Older module instances must select a validated integration when upgrading from
`organization`/`service_token_secret` inputs. Instances that already imported the
default keyspace retain it through the moved block. This module always uses the
normal change/destroy pipeline defaults after upgrading.

The service token needs permissions to create/read/write databases and branches,
manage production branch passwords, read/manage keyspaces and resize requests,
and delete owned resources. Additional backup policies require backup-policy
permissions. This module does not create service tokens or a billing account.

## Direct OpenTofu usage

Run from this directory with a configured Ravion cloud backend. For another
backend, replace `cloud {}` in your copy of `versions.tf`. Authenticate through
`PLANETSCALE_SERVICE_TOKEN_ID` and `PLANETSCALE_SERVICE_TOKEN`; never put tokens
in tfvars files.

Create `app.auto.tfvars`:

```hcl
organization = "acme"
name         = "shop-production-mysql"
region       = "us-east"
cluster_size = "PS_10"
manage_default_keyspace = false # First deployment only.
```

First deployment:

```sh
tofu init
tofu plan -out=database.tfplan
tofu apply database.tfplan
```

After the branch exists, add `manage_default_keyspace = true` to your tfvars and
keep it true for every subsequent run. Optionally change `cluster_size` or
`extra_replicas`, then run the same ordinary plan/apply commands. The next apply
imports the existing keyspace and applies its requested changes. Plan files
contain sensitive data. No targeted plan or manual `tofu import` is needed for
the default keyspace.

## Connection details

The default password reads/writes application data, not unrestricted schema
administration. With safe migrations enabled, make schema changes through
PlanetScale development branches and deploy requests; those workflows are
external to this module.

Use `host`, `port`, `username`, `password`, and `database_name` with your MySQL
driver. `connection_string` is an escaped MySQL URI. **Configure TLS certificate
and hostname verification in the driver**: MySQL clients do not share a universal
TLS URI parameter. Sensitive credentials remain in Terraform state. Importing an
existing password cannot recover its plaintext.

## Advanced configuration

Terraform settings use the same shared inputs as RDS and Aurora: **OpenTofu version
override**, **Ravion Terraform workspace name**, and **Advanced Terraform variables**.
Change and destroy pipelines come from the environment's inherited organization,
project, or environment defaults, not PlanetScale-specific module inputs. Raw
advanced variables override generated variables.

The form exposes integration, location, size, replicas, credential CIDRs, safe
migrations, and deletion protection. Advanced Terraform variables can configure
additional passwords, keyspaces, VTGate settings, and backup policies:

```yaml
additional_passwords:
  reporting:
    role: reader
    replica_enabled: true
vtgate:
  autoscaling_enabled: true
  count: 2
  max_count: 4
  target_cpu_utilization: 50
backup_policies:
  daily:
    retention_value: 14
```

Additional resources and replicas incur PlanetScale charges. Empty
`backup_policies` does not disable built-in backups. Additional keyspace shard
count is creation-only; changing it replaces that keyspace, not an online reshard.
This module does not manage additional branches, VSchema, deploy requests, or
cross-region read-only regions. Metal SKUs are supported for main/additional
keyspaces. A different disk-capacity SKU requests a resize, not branch replacement;
PlanetScale enforces resize compatibility and minimum capacity.

## Existing databases and destruction

Use a new database name for normal provisioning. An existing branch requires an
explicit branch import before applying this stack. For direct usage, also set
`manage_default_keyspace = true` once that branch is imported:

```sh
tofu import planetscale_vitess_branch.main \
  '{"organization":"acme","database":"shop-production-mysql","id":"existing-branch-id"}'
```

Review the plan before applying. Do not let two stacks own the same branch/keyspace.
To delete, disable deletion protection and **apply that change first**, then review
and run the normal destroy workflow. If the default keyspace is already managed,
Terraform deletes it before the branch. If only the first deployment ran, the
branch deletion removes its automatically-created keyspace without a separate
keyspace import or DELETE. Descendant branches are not recursively deleted;
deleting the last branch deletes the parent database.

The local API double verifies both destroy paths, but it cannot prove that the
real PlanetScale API accepts a DELETE of its default keyspace. Before production
use, verify create/adopt/resize/unprotect/destroy against an empty disposable
database. If the API refuses default-keyspace deletion, capture the redacted
status/error and stop; do not remove state or retry against valuable data. Branch
protection alone has not been verified to protect a separate keyspace DELETE.

## Requirements

| Name | Version |
| --- | --- |
| OpenTofu | >= 1.10.0 |
| planetscale/planetscale | ~> 1.11.0 |

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `organization` | PlanetScale organization slug | `string` | n/a | yes |
| `name` | Database name owned by the stack | `string` | n/a | yes |
| `region` | PlanetScale region slug | `string` | n/a | yes |
| `cluster_size` | Default-keyspace network/Metal SKU | `string` | `PS_10` | no |
| `manage_default_keyspace` | Internal adoption switch; Ravion sets automatically; true preserves legacy callers | `bool` | `true` | no |
| `deletion_protection_enabled` | Protect main branch deletion | `bool` | `true` | no |
| `safe_migrations_enabled` | Require deploy requests for main-branch DDL | `bool` | `true` | no |
| `extra_replicas` | Additional replicas; reconciled from second deployment | `number` | `0` | no |
| `vtgate` | VTGate size/count/autoscaling overrides | `object` | `{}` | no |
| `application_password` | Application password name, role, CIDRs | `object` | `{}` | no |
| `additional_passwords` | Named additional credentials | `map(object)` | `{}` | no |
| `additional_keyspaces` | Named keyspaces with size, shards, replicas | `map(object)` | `{}` | no |
| `backup_policies` | Additional backup schedules/retention | `map(object)` | `{}` | no |

See [variables.tf](variables.tf) for complete types and validations. Additional
passwords default to `reader`; additional keyspaces default to PS-10, one shard,
and no extra replicas; custom backups default to daily at 03:00 with seven-day
retention for production branches.

## Outputs

| Name | Description |
| --- | --- |
| `engine` | `vitess` |
| `organization` | PlanetScale organization slug |
| `database` | PlanetScale database name |
| `branch` | Main branch name |
| `branch_id` | Main branch ID; enables adoption on later deployments |
| `keyspace` | Discovered default-keyspace name |
| `cluster_size` | Current default-keyspace size |
| `default_keyspace_managed` | False on first deployment; true after adoption |
| `host` / `port` | Application MySQL endpoint |
| `database_name` | SQL database name |
| `username` / `password` | Application credentials; password is sensitive |
| `connection_string` | Sensitive MySQL URI; configure TLS separately |
| `tls_required` | `true` |
| `dashboard_url` | PlanetScale branch dashboard |
| `additional_credentials` | Sensitive map of additional credentials |

## Verification

```sh
tofu init -backend=false
tofu fmt -check
tofu validate
python3 -m unittest discover -s tests -v
```

Tests use the released provider, local state, and a local API double. They cover
ordinary first plan/apply, retry, same-apply import/resize including Metal disk
changes and replicas, simultaneous branch-setting changes, old state-address
migration, import-only recovery, drift correction, sensitive outputs, and destroy
both before and after adoption. No real database or paid resource is created.

## Learn more

- [PlanetScale Terraform provider](https://planetscale.com/docs/terraform)
- [Vitess cluster configuration](https://planetscale.com/docs/vitess/cluster-configuration)
- [PlanetScale pricing](https://planetscale.com/pricing)
