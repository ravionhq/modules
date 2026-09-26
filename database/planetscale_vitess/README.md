# PlanetScale MySQL

Managed PlanetScale MySQL with application credentials, safe migrations, and in-place cluster resizing.

## Overview

This OpenTofu root stack owns one PlanetScale Vitess database, its `main` branch,
the automatically created default keyspace, and a generated application password.
It uses the official `planetscale/planetscale` provider. PlanetScale resources do
not support AWS-style tags, so this stack has no tags input or AWS provider.

Defaults are PS-10, safe migrations enabled, deletion protection enabled, and a
non-expiring `readwriter` application credential. PlanetScale's built-in automatic
backups and default VTGate configuration remain in effect. Additional keyspaces,
replicas, passwords, VTGate settings, and backup policies are optional.

## Two-stage provisioning

The provider automatically creates the default keyspace with the branch, but
requires importing it before Terraform can resize it. Imports happen during
planning, so a fresh database needs two plan/apply pairs in the **same workspace**:

1. Target only `planetscale_vitess_branch.main` to create the database and main branch.
2. Run a full plan. Discover the default keyspace by its `is_default` flag, import
   it declaratively, and apply the remaining configuration.

The supplied [change pipeline](pipelines/change.yml) performs both stages and
serializes the entire sequence by stack ID. Each apply consumes its corresponding
saved plan. It follows Ravion's normal approval behavior. A retry repeats the
branch stage safely and then continues the full plan; it does not remove resources
from state or toggle resources off during bootstrap.

On later runs, branch `cluster_size` changes are ignored because that provider
attribute would replace the branch. The keyspace resource owns sizing and extra
replicas and updates them in place. The import block is a no-op once imported.

**Use this directory as a root stack**, not a nested Terraform module: its import
block and Ravion backend belong at the root. Do not replace the two-stage workflow
with the standard single-stage change pipeline for an empty workspace.

## Ravion setup

1. Create a pipeline in the Ravion project and install `pipelines/change.yml` as
   its configuration. With an existing pipeline ID:

   ```sh
   ravion pipeline config apply <pipeline-id> \
     --file database/planetscale_vitess/pipelines/change.yml
   ```

2. Store the PlanetScale service token in AWS Secrets Manager as JSON with
   `service_token_id` and `service_token` keys. The runner must be able to read
   that secret (and decrypt its KMS key, if applicable).
3. Add **PlanetScale MySQL** (`rvn-planetscale-vitess`). Set the organization,
   database region, service token secret, execution environment, and provisioning
   pipeline ID. The execution environment controls the runner location, not the
   PlanetScale database location.
4. Deploy and connect the application using the sensitive stack outputs.

The pipeline is project-owned and installed once; publishing a module definition
does not create project pipelines. The default Ravion destroy pipeline is used
for destruction. The supplied pipeline's group lock uses the same
organization-scoped stack key as that standard destroy pipeline.

The service token needs permissions to create/read/write databases and branches,
manage production branch passwords, read/manage keyspaces and resize requests,
and delete the resources it owns. Additional backup policies require backup-policy
permissions. Configure these in PlanetScale before provisioning; this module does
not create service tokens or a billing account.

## Direct OpenTofu usage

Run from this directory using a configured Ravion cloud backend. For another
backend, replace `cloud {}` in your copy of `versions.tf` with that backend.
Authenticate using `PLANETSCALE_SERVICE_TOKEN_ID` and `PLANETSCALE_SERVICE_TOKEN`;
do not put service tokens in tfvars files.

Create `app.auto.tfvars`:

```hcl
organization = "acme"
name         = "shop-production-mysql"
region       = "us-east"
cluster_size = "PS_10"
```

Then run both stages with the same configuration and backend:

```sh
tofu init
tofu plan -target=planetscale_vitess_branch.main -out=bootstrap.tfplan
tofu apply bootstrap.tfplan
tofu plan -out=database.tfplan
tofu apply database.tfplan
```

The targeted stage is a bootstrap workaround for the provider lifecycle, not a
replacement for the second, complete plan. Plan files contain sensitive data.

## Connection details

The default password can read and write application data. It is not an unrestricted
schema-administration credential. With safe migrations enabled, make schema
changes through PlanetScale development branches and deploy requests. Such schema
deployment workflows are external to this module.

Use `host`, `port`, `username`, `password`, and `database_name` with your MySQL
driver. `connection_string` provides an escaped MySQL URI. **Configure TLS with
certificate and hostname verification in the driver**: MySQL clients do not share
a universal TLS URI parameter. Credentials are marked sensitive but remain in
Terraform state. Importing an existing password cannot recover its plaintext.

## Advanced Terraform variables

The Ravion form exposes location, size, safe migrations, and deletion protection.
Advanced Terraform variables use the typed inputs below, for example:

```yaml
extra_replicas: 1
application_password:
  cidrs: [203.0.113.10/32]
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
`backup_policies` does not disable the platform's built-in backups. Keyspace shard
count is creation-only: changing it replaces that additional keyspace; it does not
perform an online reshard. This first release does not manage additional branches,
VSchema, deploy requests, cross-region read-only regions, or Metal disk selection.

## Existing databases and destruction

Use a new database name for normal provisioning. Existing databases require an
explicit branch import into this workspace before running the pipeline:

```sh
tofu import planetscale_vitess_branch.main \
  '{"organization":"acme","database":"shop-production-mysql","id":"existing-branch-id"}'
```

Review the full plan before applying: the module then imports the default
keyspace, reconciles its configuration, and creates application credentials. Do
not let two stacks own the same branch/keyspace.

To delete, disable deletion protection and **apply that change first**, then run
the destroy workflow. Descendant branches are not recursively deleted. Deleting
the last branch deletes the parent database. Branch identity and region changes
are not database migrations.

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
| `region` | PlanetScale region slug, e.g. `us-east` | `string` | n/a | yes |
| `cluster_size` | Main keyspace network-storage SKU | `string` | `PS_10` | no |
| `deletion_protection_enabled` | Main branch deletion protection | `bool` | `true` | no |
| `safe_migrations_enabled` | Require deploy requests for main-branch DDL | `bool` | `true` | no |
| `extra_replicas` | Extra main-keyspace replicas | `number` | `0` | no |
| `vtgate` | Size, count, autoscaling, maximum count, target CPU overrides | `object` | `{}` (platform defaults) | no |
| `application_password` | Name, role and CIDRs for the application password | `object` | `{}` (`application`, `readwriter`, no CIDR restriction) | no |
| `additional_passwords` | Credentials keyed by name; role, CIDRs, replica/direct routing and optional TTL | `map(object)` | `{}` | no |
| `additional_keyspaces` | Keyspaces keyed by name; size, shards and extra replicas | `map(object)` | `{}` | no |
| `backup_policies` | Policies keyed by name; target, schedule, frequency and retention | `map(object)` | `{}` | no |

See [variables.tf](variables.tf) for complete object types, defaults and validations.
Additional passwords default to `reader`; additional keyspaces default to PS-10,
one shard and no extra replicas; custom backup policies default to daily at 03:00
with seven-day retention for production branches.

## Outputs

| Name | Description |
| --- | --- |
| `engine` | `vitess` |
| `organization` | PlanetScale organization slug |
| `database` | PlanetScale database name |
| `branch` | Main branch name |
| `branch_id` | Main branch ID |
| `keyspace` | Discovered default keyspace name |
| `cluster_size` | Managed main-keyspace size |
| `host` | Application MySQL host |
| `port` | `3306` |
| `database_name` | SQL database name |
| `username` | Generated application username |
| `password` | Sensitive application password |
| `connection_string` | Sensitive MySQL URI; configure driver TLS separately |
| `tls_required` | `true` |
| `dashboard_url` | PlanetScale branch dashboard |
| `additional_credentials` | Sensitive map of additional connection credentials |

## Verification

```sh
tofu init -backend=false
tofu validate
python3 -m unittest discover -s tests -v
```

The lifecycle test uses the actual provider against a local API double and local
state. It exercises fresh bootstrap, retry, import, in-place resizing, no-op
replanning, and sensitive outputs. No real database or paid resource is created.
Live API acceptance testing is still required before production use.

## Learn more

- [PlanetScale Terraform provider](https://planetscale.com/docs/terraform)
- [Vitess cluster configuration](https://planetscale.com/docs/vitess/cluster-configuration)
- [PlanetScale pricing](https://planetscale.com/pricing)
