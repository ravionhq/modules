# Ravion GCP project setup (Terraform)

Connects one Google Cloud project to Ravion with **workload identity
federation**. No service account keys are created or shared: Ravion's
credentials-broker signs a short-lived OIDC token, Google STS exchanges it for
a federated token, and the broker impersonates one of the service accounts
this module creates. The customer runs the module from Cloud Shell with their
own credentials (see [`tutorial.md`](tutorial.md)); it ends by reporting the
setup to Ravion, which verifies it before marking the connection connected.

Version: [`VERSION`](VERSION) · Changes: [`CHANGELOG.md`](CHANGELOG.md) ·
Purposes and permissions: [`catalog.gen.tf.json`](catalog.gen.tf.json)
(generated, do not edit).

## What it creates

| Resource                                                                                               | Purpose                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `google_project_service` (×11)                                                                         | Enables the APIs Ravion calls (`enable_apis = false` to skip).                                                                                                                                                                                                                                                        |
| Workload identity pool `ravion` + OIDC provider `ravion-<connection>`                                  | Trusts `issuer_uri` (default `https://oidc.ravion.com`). No `allowed_audiences`, so tokens must carry the provider's own resource name as `aud`.                                                                                                                                                                      |
| Provider attribute condition                                                                           | Only tokens minted for **this** connection (`rvn:connection == ravion_account_id`, `sub == rvn:gcp:<id>:purpose:<rvn:purpose>`) by Ravion's API or automation workers (`rvn:caller_service in allowed_callers`). Ravion is a multi-tenant issuer, so this condition is what keeps other Ravion customers' tokens out. |
| Attribute mapping                                                                                      | `google.subject = sub`, `attribute.connection`, `attribute.purpose`, `attribute.caller` from the `rvn:*` claims. Audit logs show the subject, so every call names its Ravion purpose.                                                                                                                                 |
| Tier service accounts `ravion-read`, `ravion-ops`, `ravion-compute`, `ravion-sandbox`, `ravion-deploy` | What Ravion impersonates. Each holds a project custom role `ravion_<tier>` with exactly the permissions of its purposes.                                                                                                                                                                                              |
| `roles/iam.workloadIdentityUser` per purpose                                                           | On each tier service account, for `principalSet://…/attribute.purpose/<purpose>` of that tier's purposes only. A token for `logs-read` cannot impersonate `ravion-deploy`.                                                                                                                                            |
| `ravion-runner`                                                                                        | Attached to the VMs that run pipeline steps and Terraform. Holds `runner_sa_roles`.                                                                                                                                                                                                                                   |
| `ravion-sandbox-host`                                                                                  | Attached to sandbox hosts. Holds `sandbox_host_sa_roles`.                                                                                                                                                                                                                                                             |
| `roles/iam.serviceAccountUser`                                                                         | `ravion-compute` on `ravion-runner`, `ravion-sandbox` on `ravion-sandbox-host` only (never project-wide).                                                                                                                                                                                                             |
| `terraform_data.callback`                                                                              | `curl`s `callback_url` with `Authorization: Bearer <onboarding_token>` and the JSON below. Re-runs whenever the reported setup changes.                                                                                                                                                                               |

Callback body:

```json
{
  "ravion_account_id": "gcpact_…",
  "project_id": "my-project",
  "project_number": "123456789012",
  "workload_identity_provider": "projects/123456789012/locations/global/workloadIdentityPools/ravion/providers/ravion-…",
  "pool_id": "ravion",
  "provider_id": "ravion-…",
  "issuer_uri": "https://oidc.ravion.com",
  "service_accounts": {
    "read": "ravion-read@…",
    "ops": "…",
    "compute": "…",
    "sandbox": "…",
    "deploy": "…"
  },
  "attached_service_accounts": {
    "runner": "ravion-runner@…",
    "sandbox-host": "ravion-sandbox-host@…"
  },
  "setup_version": "1.0.0"
}
```

## Tiers and custom roles

GCP has no session policies, so Ravion's per-purpose scoping on GCP is the
**tier**. Every tier uses a custom role generated from the purpose catalog;
no predefined role is used for the tiers. Predefined roles are only used for
the two attached service accounts, where the customer decides the scope:

| Tier      | Custom role      | Notes                                                                                                                                                                                                |
| --------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `read`    | `ravion_read`    | Inventory, logs, metrics, images, and the healthcheck.                                                                                                                                               |
| `ops`     | `ravion_ops`     | Secret Manager reads, log/metric writes, object uploads to existing buckets.                                                                                                                         |
| `compute` | `ravion_compute` | Runner VM lifecycle; may act as `ravion-runner` only.                                                                                                                                                |
| `sandbox` | `ravion_sandbox` | Sandbox hosts, their buckets and firewall rules; may act as `ravion-sandbox-host` only.                                                                                                              |
| `deploy`  | `ravion_deploy`  | Project IAM policy, service accounts, services. **Project-administrator equivalent** (`resourcemanager.projects.setIamPolicy`), which mirrors the AWS `deploy-infrastructure` purpose (`Action: *`). |

`runner_sa_roles` defaults to `roles/editor`: the AWS equivalent runs applies
with `AdministratorAccess`, so Terraform can create whatever a module
declares. Narrow it if you prefer; applies that need more fail with
permission errors. `roles/editor` cannot change IAM policies, so modules that
manage IAM also need `roles/resourcemanager.projectIamAdmin`.

Limits that matter: a custom role holds at most 3,000 permissions and a
project at most 300 custom roles; the attribute condition is at most 4,096
characters.

## Versions

Each version is tagged `rvn-gcp-setup@<version>` in this repository, and
[`CHANGELOG.md`](CHANGELOG.md) says what it changes. The setup command Ravion
shows fetches that tag, checks that its files are exactly the ones Ravion
expects for the version (by their git tree id), and copies the module into
`~/ravion-gcp-setup/<connection id>` in Cloud Shell, where the Terraform state
of earlier versions is kept. To see what an upgrade changes before applying
it, diff the two tags, or run `terraform plan` with the new version.

Ravion never holds `iam.roles.update` on its own roles: upgrades always run
with your credentials.

## Uninstalling and reinstalling

`terraform destroy` removes everything, after which Ravion can no longer reach
the project. Deleted workload identity pools and providers are kept for 30
days and their ids cannot be reused in that time; reinstall with a different
`pool_id`/`provider_id`, or undelete them (`gcloud iam workload-identity-pools
undelete`). Deleted custom roles are undeleted by the Google provider when
recreated.

## Org policies that can block the setup

- `constraints/iam.workloadIdentityPoolProviders` must allow
  `https://oidc.ravion.com`.
- `constraints/iam.allowedPolicyMemberDomains` (domain-restricted sharing) may
  reject `principalSet://` members.
- `constraints/iam.disableServiceAccountCreation` blocks the service accounts.
