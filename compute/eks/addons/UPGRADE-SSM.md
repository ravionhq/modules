# Upgrade EKS management from Operator to SSM

This is a staged cutover. New configurations install no Ravion Operator and mint
no Operator credentials. The new cluster module adds a **dedicated** private ARM
EC2 relay; existing Kubernetes nodes are not reused. This document describes
operations for the cluster owner; none are performed by module publishing.

## 1. Inventory and prepare access

1. Back up the existing state securely: it contains the old WorkOS client secret.
   Record the credential resource ID/WorkOS secret ID, Helm release namespaces,
   and Secrets Manager ARN before making changes. Keep the original module ref
   and provider lock file available until revocation and cleanup are verified.
2. Preserve `observability_namespace` explicitly if it was inherited from an
   overridden `ravion_operator_namespace` (including `ravion-beacon`). Preserve
   `logs_namespace`, `metrics_namespace`, and `grafana_namespace` overrides too.
   The new default is still `ravion-operator`; changing namespaces does **not**
   migrate PVCs. Preserve Helm values, S3 bucket settings and AMP workspace IDs.
3. Copy old deployment namespaces to `workload_namespaces` and old observation
   scopes to `observed_namespaces`, including advanced overrides. Form fields
   migrate their old deployment/observation identifiers; advanced Terraform
   variable maps must be updated explicitly. Their sorted, deduplicated union
   controls namespace bootstrap and namespace-scoped Helm inventory reads.
   Preserve the old namespace-creation setting. The bootstrap Helm resource
   address, `ravion-operator-namespaces` release/chart, and `kube-system` release
   namespace are unchanged; namespaces remain protected by Helm's keep policy.
   Each namespace in the union gets a Role/RoleBinding granting `ravion:readers`
   get/list **all Secrets**, needed for Helm storage inventory/drift. RBAC cannot
   limit Secret listing to Helm labels. No ClusterRole grants Secret access;
   no Secret write, exec or port-forward permissions are granted. An empty union
   grants no Secret reads. Disabling namespace creation preserves these read
   grants for externally provisioned namespaces; scope removal retracts RBAC
   but keeps Namespace objects. Shared `ravion-operator` is not implicitly added.
4. Deploy the cluster module with private API access enabled, a private subnet,
   and working SSM connectivity. NAT or existing `ssm` and `ssmmessages` interface
   endpoints with private DNS are required; older regional agents may also need
   `ec2messages`. Endpoint security groups must admit relay HTTPS. The module
   does not create NAT or VPC endpoints. Its subnet check rejects public-IP
   subnets and supplied public subnet IDs but cannot prove route-table privacy.
5. Deploy platform `aws.account.integration_role_arn` context support before using
   the new cluster definition. It supplies the required `ravion_integration_role_arn`
   automatically; direct Terraform callers must supply the exact integration role
   in the cluster's AWS account and partition. Remove the former read/Runner
   trusted-principal list inputs and advanced overrides. Both role trusts allow
   only that integration ARN, with `sts:SetSourceIdentity` alongside `sts:AssumeRole`,
   from the six approved public source /32s documented in the cluster README.
   Caller policies must allow both actions. Source identity survives role chaining.
   Ephemeral pipeline roles no longer qualify: add-ons `aws eks get-token --role-arn`
   and workload destroy-time Helm cleanup must use the integration credential path
   and approved STS egress before this trust change is applied. The existing Runner
   security-group mapping still provides private API networking; it does not grant
   IAM trust. Verify the runtime discovers
   exactly one running relay from the cluster ARN/purpose tags, opens the pinned
   SSM session, and validates the EKS hostname/CA. Test both role assumptions,
   read-only inventory/logs and a controlled deployment. The read role cannot
   exec or port-forward. Authorized interactive operations use the admin role;
   the control plane must enforce user authorization before selecting it.
   Discovery/session transport uses customer integration-role credentials and its
   platform-managed IAM policy. EKS read/admin roles only grant DescribeCluster
   on the exact cluster in AWS IAM; the redundant admin SSM policy is removed.

The add-ons read proxy Role/RoleBinding and inventory ClusterRole/Binding are new.
AWS View omits nodes/live metrics. If you need them before retiring
Operator, install the `charts/observability-access` chart with the desired service
names/namespaces and `clusterInventoryEnabled=true` as a temporary bootstrap,
then import that Helm release into
`helm_release.observability_access[0]` when upgrading. Otherwise verify inventory
for workloads first and complete node/log-query validation after the add-ons upgrade.
Never approve replacement/deletion of Loki, Prometheus PVCs, AMP, buckets, or
workload namespaces as a side effect of this cutover.

## 2. Revoke and remove Operator before detaching its state

**Preferred:** while still on the old module/provider configuration, set
`ravion_operator_enabled = false` (or the equivalent legacy `beacon_enabled`),
inspect the plan, and apply that retirement separately. The old resource's
provider Delete must successfully revoke the WorkOS credential using the
supported retired-credential deletion endpoint. The old Helm releases and AWS
Secrets Manager mirror are removed in the same retirement. Leave the old
namespace setting intact so observability does not move. Do not continue if
revocation fails; preserve state and fix provider/API access first.

Verify all of the following before detaching any leftover credential state:

- The recorded WorkOS secret has been revoked and cannot mint new tokens.
- The Operator deployment, its RBAC and service account have been removed.
- The `ravion-beacon` and `ravion-beacon-credential` Helm releases are gone from
  their **actual** namespace; use `helm list -A` and inspect those releases.
- The Kubernetes Secret `ravion-beacon-credential` and the Secrets Manager mirror
  `ravion/beacon/<cluster>/credential` have been deleted. Confirm the ARN recorded
  in inventory rather than assuming the deterministic name is sufficient.
- Retained workload namespaces, observability Helm releases, persistent volumes,
  Loki S3 data, AMP workspace and vendor ESO secrets still exist and work.

If old Terraform retirement cannot be used, call the supported credential-delete
API through the retained provider/administrative tooling **first**, verify WorkOS
revocation, then explicitly uninstall those two legacy Helm releases and delete
both credential copies. Do not delete the shared `ravion-operator` or
`ravion-beacon` namespace: it may contain observability and application data.
Do not revoke the shared WorkOS application/client; revoke only this cluster's
recorded secret. There is no automatic fallback that silently abandons it.

Only after revocation and cleanup are verified may an orphaned credential be
detached, using its exact address from `tofu state list`, for example:

```sh
tofu state rm 'module.eks_addons.ravion_operator_credential.this[0]'
```

Root module executions omit `module.eks_addons.`. Older addresses may differ;
inspect state rather than copying an address blindly. `state rm` does not revoke
credentials or remove cloud resources. State backup retention must account for
the revoked secret still being present in historical state snapshots.

## 3. Upgrade add-ons and verify the final plan

The new configuration has no Ravion provider dependency. **Legacy state still
requires its original provider source/schema until the custom-provider resource
has been destroyed or detached.** The former source in this branch was
`ravion-providers.ngrok.app/ravion/ravion`; use the actual source/locked version
from your state. Do not replace it with an assumed `hashicorp/ravion` provider.
If the old registry is unavailable, retain/install its exact binary with a
provider mirror for the migration; do not regenerate production lock checksums
from a local-only mirror.

There is deliberately no custom-provider `removed` block in the new module:
even a non-destructive block forces new installations to resolve that retired
provider. Detach only after the verified cleanup above, **before initializing
the new configuration**. Remove obsolete `ravion_operator_*` / `beacon_*` inputs
and output references from callers. Use the cluster `ravion_access_*` outputs.

AWS/Helm `removed { lifecycle { destroy = false } }` blocks protect against
accidental infrastructure destruction if stale state entries remain. They are
**not an uninstall or revocation mechanism** and do not make an abandoned
installation retired. A plan saying resources will no longer be managed is only
acceptable after their actual cleanup has been verified.

Review a complete plan: shared release names, namespaces, PVCs, S3 bucket and
AMP workspace should be stable; namespace bootstrap remains independent. Apply,
then check GET service-proxy Loki queries and managed Prometheus queries with
the read role. Query POST form parameters must be converted to URL query
parameters for GET; no observer pod-forward grant is provided. Custom Prometheus
endpoints require explicitly provisioned read proxy RBAC in their namespace.

## Operational limits

- One relay is a single connection-availability point. EC2 replacement/AMI
  updates interrupt sessions; reconnect by rediscovering the running instance.
- `t4g.micro` provides practical SSM memory headroom. `t4g.nano` is available but
  has less headroom for concurrent sessions. Both are ARM64 AL2023, 8 GiB encrypted
  gp3, no public IP/key pair/inbound rules, IMDSv2, and SSM core instance IAM only.
- The platform-managed customer integration-role policy owns SSM transport and
  must enforce the pinned document, relay target and session ownership. The EKS
  access roles grant no SSM permissions. IAM is additive.
- IAM/SSM session teardown and actual AWS/network behavior require live cutover
  verification. Mocked plan and chart tests do not establish live connectivity.
- Vendor ingestion/ESO credentials are preserved. Vendor query credentials are
  references only; vendors remain ship-only destinations unless a compatible
  credential-aware query backend is separately provided.
