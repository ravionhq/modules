# ClickHouse on EKS

Self-hosted, replicated [ClickHouse](https://clickhouse.com) on an existing EKS cluster, managed by the
[Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator). Everything, including
backups and cold data, stays in your AWS account.

The module creates:

- The Altinity clickhouse-operator, watching only the installation's namespace, with namespaced RBAC.
- A ClickHouse Keeper ensemble (3 nodes by default) for replication and distributed DDL.
- A ClickHouse cluster named `main` of the shards and replicas you choose, spread across availability
  zones and never two replicas of a shard on one node, with EBS volumes the operator grows in place.
- `admin`, `writer` and `reader` users with generated passwords in AWS Secrets Manager, copied into the
  cluster by the External Secrets Operator. Passwords never appear in Terraform state, plan files or Helm
  values.
- An encrypted, versioned, private S3 bucket (or an existing one), and an IAM role the ClickHouse pods use
  through EKS Pod Identity, scoped to that bucket.
- Scheduled backups of every shard to S3 with [clickhouse-backup](https://github.com/Altinity/clickhouse-backup).
- A `tiered` storage policy with an S3 `cold` volume for old data.
- Prometheus metrics for ClickHouse, Keeper and the operator, with optional PodMonitors and an optional
  OTLP push.
- Optionally: TLS on the native and HTTP interfaces with certificates from cert-manager, an empty database,
  NetworkPolicies, a PriorityClass and a dedicated Karpenter NodePool.

## Usage

```hcl
module "clickhouse" {
  source = "git::https://github.com/ravionhq/modules.git//database/clickhouse?ref=v1.0.0"

  cluster_name = "my-eks-cluster"
  region       = "us-east-1"
  name         = "analytics"
  namespace    = "analytics"

  database_name = "events"

  # Optional: push metrics to the EKS add-ons module's OTLP receiver.
  metrics_otlp_endpoint = module.eks_addons.otlp_http_endpoint
}
```

Applications in the cluster connect to `host` on port 8123 (HTTP) or 9000 (native), or with `tls_enabled`
on 8443 (HTTPS) and 9440 (native over TLS); see [TLS](#tls). Each user's
Secrets Manager secret (`admin_secret_arn`, `writer_secret_arn`, `reader_secret_arn`) is JSON:

```json
{
  "username": "writer",
  "password": "...",
  "host": "clickhouse-analytics.analytics.svc.cluster.local",
  "http_port": 8123,
  "native_port": 9000,
  "database": "events",
  "cluster": "main"
}
```

The same keys are in Kubernetes Secrets in the namespace (`<name>-admin`, `<name>-writer`, `<name>-reader`).

## Prerequisites

- OpenTofu 1.11 or newer (ephemeral resources and write-only arguments).
- The `eks-pod-identity-agent` EKS add-on, when backups or the cold tier are on.
- The [External Secrets Operator](https://external-secrets.io) (`external-secrets.io/v1`). By default the
  module creates a namespaced `SecretStore` with no `auth` block, which uses the controller's own AWS
  credentials, so its role needs `secretsmanager:GetSecretValue` on the secrets (and `kms:Decrypt` on
  `secrets_kms_key_arn` if set). Set `external_secrets.cluster_secret_store_name` to use an existing
  `ClusterSecretStore` instead; it must allow the installation's namespace.
- A StorageClass that allows volume expansion (`gp3` by default).
- For `dedicated_node_pool`, Karpenter and an `EC2NodeClass`. For `metrics_pod_monitors_enabled`, the
  Prometheus Operator CRDs. For `tls_enabled`, [cert-manager](https://cert-manager.io), such as from the EKS
  add-ons module.

The Terraform runner needs the AWS CLI and network access to the cluster API; the provider authenticates
with `aws eks get-token`, assuming `ravion_runner_role_arn` when it is set.

## Users

| User | For | Access |
| ---- | --- | ------ |
| `admin` | Operations and user management | Everything, including SQL-driven access management |
| `writer` | Ingestion and schema migrations | `SELECT, INSERT, ALTER, CREATE, DROP, TRUNCATE, OPTIMIZE, SHOW, dictGet` on the database (every database when `database_name` is null), and `CLUSTER` for `ON CLUSTER` DDL |
| `reader` | Dashboards and APIs | `SELECT, SHOW, dictGet`, `readonly = 2`, held to `reader_limits` |

The reader may change settings per query, but constraints keep `max_execution_time`, `max_memory_usage`
and `max_concurrent_queries_for_user` between 1 and their ceilings, so it can neither raise them nor set
them to 0 (unlimited).

Queries between shards run as the user who sent them, authenticated with a cluster secret the operator
generates, not as the built-in `default` user.

### Rotating passwords

Bump `password_version`. Every user gets a new password in Secrets Manager, External Secrets refreshes the
Kubernetes Secrets at once, and the operator and ClickHouse pods restart (one at a time) to read them.
Clients must read the new values; expect a short window where clients holding the old password fail.

## Database engine

With `database_name` set, a post-install job creates it on every server once all of them have joined the
cluster. `Replicated` (the default) replicates `CREATE TABLE` and `ALTER` to every replica on its own;
with `Atomic`, run DDL with `ON CLUSTER main`. Either way, use the `Replicated*MergeTree` engines for
tables whose data should be replicated.

## Shards and replicas

Start with one shard: a single ClickHouse server handles billions of rows, and a shard grows with CPU,
memory and volume size. Adding shards later means creating new tables or redistributing existing data, so
add shards only when one server cannot hold the data. Two replicas per shard keep data available while a
node or zone is down. With `zone_spread = "required"`, two replicas of one shard are never scheduled in the
same zone.

## Backups and restore

Each ClickHouse pod runs `clickhouse-backup server` next to the server, reading the same volume. On
`backup_schedule` (UTC) a CronJob asks one replica of each shard to run `create_remote`, waits until the
upload finishes, and fails if any shard has no successful backup. Backups land in
`s3://<bucket>/backup/main/<shard>/`, parts on the cold tier in `backup-object-disks/`, and each shard
keeps `backup_retention_count` backups. Watch the CronJob's failed jobs to alert on missed backups.

To restore a shard, run on one of its replicas:

```bash
kubectl -n <namespace> exec -it chi-<name>-main-<shard>-0-0 -c clickhouse-backup -- clickhouse-backup list remote
kubectl -n <namespace> exec -it chi-<name>-main-<shard>-0-0 -c clickhouse-backup -- clickhouse-backup restore_remote <backup>
```

Repeat for every shard with the same backup name. The other replicas of each shard catch up through
replication. Add `--table=<database>.<table>` to restore a single table, or `--rm` to drop existing tables
first. To rebuild after losing the cluster, create the installation again with the same bucket
(`s3_bucket_creation_enabled = false`, `s3_bucket_name = "<bucket>"`) and restore.

## Cold tier

With `cold_storage_enabled`, every server has a storage policy `tiered` with a `hot` volume (the EBS
volume) and a `cold` volume on `s3://<bucket>/cold/`, read through a local cache of
`cold_storage_cache_size`. Tables keep the `default` policy unless they opt in:

```sql
CREATE TABLE events
(
    timestamp DateTime,
    ...
)
ENGINE = ReplicatedMergeTree
ORDER BY (timestamp)
TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold'
SETTINGS storage_policy = 'tiered';
```

When the hot volume runs nearly full, ClickHouse also moves the oldest parts of `tiered` tables to `cold`.

## TLS

With `tls_enabled`, every server also serves the native protocol over TLS on 9440 and HTTPS on 8443. A
single cert-manager certificate covers the Service, every replica's pod and `localhost`, plus
`tls_extra_dns_names`; it is mounted into the pods as a directory, so ClickHouse picks up a renewed
certificate without a restart. The cluster is marked `secure` in the ClickHouseInstallation, so queries
between shards go over 9440 with TLS too, verified against the same CA.

Clients verify the `tls_server_name` output and trust the `ca.crt` of the Secret named by the
`tls_ca_secret_name` output, whichever CA issued it. Copy only `ca.crt` to clients: the Secret also holds
the server's private key.

```bash
clickhouse-client --host clickhouse-analytics.analytics.svc.cluster.local --secure --port 9440 \
  --user writer --password "$PASSWORD"
```

`tls_disable_plaintext_ports` closes 9000 and 8123 on the servers, their pods and the Service, and drops
them from the NetworkPolicy. What used them moves on its own: the operator talks to the servers over HTTPS
on 8443, the liveness and readiness probes use HTTPS, the clickhouse-backup sidecar connects to 9440 on
`localhost`, and the database job connects to 9440 and verifies the CA. The `http_port`, `native_port` and
`http_endpoint` outputs are then null. The connection details in the Secrets Manager secrets keep listing
the plaintext ports, as they are written only when `password_version` changes; read the TLS ports from the
`https_port` and `secure_native_port` outputs.

`tls_ca_source` picks what issues the certificate: `self_signed` (a CA created in the namespace, the
default), `issuer` (an existing cert-manager Issuer or ClusterIssuer, `tls_issuer = { name, kind, group }`)
or `secret` (an existing CA key pair Secret, `tls_ca_secret_name`). An existing issuer must put its CA in
the certificate Secret's `ca.crt`, as the CA and AWS Private CA issuers do.

For **AWS Private CA**, install the [aws-privateca-issuer](https://github.com/cert-manager/aws-privateca-issuer)
plugin, give its service account `acm-pca:DescribeCertificateAuthority`, `acm-pca:IssueCertificate` and
`acm-pca:GetCertificate` on the CA through EKS Pod Identity, create an `AWSPCAClusterIssuer` for the CA, and
set `tls_issuer = { name = "<issuer>", kind = "AWSPCAClusterIssuer", group = "awspca.cert-manager.io" }`.

Not included in this version:

- Traffic between ClickHouse and Keeper (2181), between Keeper nodes (Raft, 9444) and replication between
  replicas (interserver HTTP, 9009) stays unencrypted inside the namespace. The pinned operator writes
  `interserver_http_port` and its pod and Service ports itself and has no setting for
  `interserver_https_port`. Its secure Keeper mode (client port 2281, Raft over TLS) is new in this
  operator line, falls back to process-based liveness probes, and leaves the operator's own Keeper client
  unable to connect. Keep those ports inside the namespace with `network_policy_enabled`.
- The operator encrypts its connection to the servers but, as by default, does not verify their
  certificate: its CA setting is read once at startup from a Secret that would not exist yet.
- The clickhouse-backup sidecar's API on 7171, which the backup job calls, stays HTTP: the sidecar reads a
  TLS certificate only at startup and would keep serving an expired one after renewal.
- Clients are not required to present certificates (mutual TLS).

## Metrics

| Component | Endpoint | Annotation |
| --------- | -------- | ---------- |
| ClickHouse | `:9363/metrics` | `prometheus.io/scrape: "true"` |
| Keeper | `:7000/metrics` | `prometheus.io/scrape: "true"` |
| Operator | `:9999/metrics` | `prometheus.io/scrape: "true"` |

Any annotation-based scraper picks them up. `metrics_pod_monitors_enabled` adds Prometheus Operator
PodMonitors, with `metrics_pod_monitor_labels` for a Prometheus that selects by label.
`metrics_otlp_endpoint` runs one OpenTelemetry collector that scrapes the three and pushes over OTLP/HTTP,
for metrics backends that receive rather than scrape. The EKS add-ons module's `otlp_http_endpoint` is
such a receiver: it forwards to the metrics destinations chosen there.

## Several installations on one cluster

Every installation has its own operator watching only its own namespace, and every cluster-scoped object
it creates is named after the installation. The operator CRDs are shared by the whole cluster, so set
`operator_crds_management_enabled = false` on all installations but one, the one running the newest
operator, so an older operator never downgrades them.

## Deleting

Volumes are kept when the installation is deleted unless `volume_reclaim_policy = "Delete"`. The bucket and
its backups are kept unless `s3_force_destroy` is set. Credential secrets stay recoverable for
`secrets_recovery_window_in_days`.

## Requirements

| Name | Version |
|------|---------|
| opentofu | >= 1.11.0 |
| aws | >= 6.0 |
| helm | >= 3.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster to install ClickHouse on. | `string` | n/a | yes |
| region | AWS region of the cluster. Null uses the provider's default region. | `string` | `null` | no |
| ravion_runner_role_arn | IAM role `aws eks get-token` assumes to reach the Kubernetes API. Null uses the caller's own credentials. | `string` | `null` | no |
| name | Name of the ClickHouse installation. Prefixes its Kubernetes objects, Services, secrets and AWS resources. Up to 24 lowercase letters, digits and hyphens. | `string` | n/a | yes |
| namespace | Kubernetes namespace for the operator, ClickHouse, Keeper and backups. | `string` | n/a | yes |
| namespace_creation_enabled | Create the namespace. Turn off when it is managed elsewhere. | `bool` | `true` | no |
| tags | A map of tags to assign to AWS resources. | `map(string)` | `{}` | no |
| operator_chart_version | Version of the Altinity clickhouse-operator Helm chart. The operator image follows the chart's appVersion. | `string` | `"0.27.4"` | no |
| operator_crds_management_enabled | Install and upgrade the operator's cluster-scoped CRDs on every apply. With several installations on one cluster, keep this on for exactly one of them (the one with the newest operator) so an older operator never downgrades the shared CRDs. | `bool` | `true` | no |
| operator_resources | Requests and limits for the operator container. | `object({ cpu_request = optional(string, "100m") memory_request = optional(string, "128Mi") memory_limit = optional(string, "512Mi") })` | `{}` | no |
| clickhouse_image | ClickHouse server image, including its tag. Pin an LTS release. | `string` | `"clickhouse/clickhouse-server:26.8.36.3"` | no |
| shard_count | Number of shards. One shard scales vertically a long way; adding shards later means redistributing existing data, so start with 1 unless one server cannot hold the data. | `number` | `1` | no |
| replica_count | Replicas per shard. 2 or more keeps the data available while a node or zone is down. Replicated tables need ClickHouse Keeper, which this module always runs. | `number` | `2` | no |
| clickhouse_resources | Requests and limits for each ClickHouse server. ClickHouse caps its own memory at 90% of the container limit, so keep memory_limit set. | `object({ cpu_request = optional(string, "1") cpu_limit = optional(string) memory_request = optional(string, "4Gi") memory_limit = optional(string, "4Gi") })` | `{}` | no |
| clickhouse_volume_size | Size of each ClickHouse server's data volume. Raising it later grows the volumes in place. | `string` | `"50Gi"` | no |
| storage_class_name | StorageClass for ClickHouse and Keeper volumes. It must allow volume expansion for size increases to apply. | `string` | `"gp3"` | no |
| volume_reclaim_policy | What happens to the data volumes when the installation is deleted: Retain keeps them, Delete removes them. | `string` | `"Retain"` | no |
| clickhouse_settings | Extra server settings, keyed by path as the operator expects (for example `max_concurrent_queries` or `logger/level`). | `map(string)` | `{}` | no |
| keeper_image | ClickHouse Keeper image, including its tag. Keep it on the same release as clickhouse_image. | `string` | `"clickhouse/clickhouse-keeper:26.8.36.3"` | no |
| keeper_replica_count | Keeper nodes. 3 tolerates losing one; 1 has no redundancy and suits development only. | `number` | `3` | no |
| keeper_resources | Requests and limits for each Keeper node. | `object({ cpu_request = optional(string, "250m") cpu_limit = optional(string) memory_request = optional(string, "512Mi") memory_limit = optional(string, "1Gi") })` | `{}` | no |
| keeper_volume_size | Size of each Keeper node's volume (logs and snapshots). | `string` | `"10Gi"` | no |
| zone_spread | How replicas of a shard, and Keeper nodes, spread across availability zones: preferred spreads when capacity allows, required refuses to schedule two replicas of a shard in one zone. | `string` | `"preferred"` | no |
| priority_class | Create a PriorityClass for ClickHouse and Keeper so they are preempted and evicted after ordinary workloads. | `object({ enabled = optional(bool, false) value = optional(number, 1000000) })` | `{}` | no |
| dedicated_node_pool | Run ClickHouse and Keeper on a tainted Karpenter NodePool of their own. Needs Karpenter and an EC2NodeClass on the cluster. | `object({ enabled = optional(bool, false) node_class_name = optional(string, "default") capacity_types = optional(list(string), ["on-demand"]) instance_categories = optional(list(string), ["r", "m"]) architectures = optional(list(string), ["amd64"]) cpu_limit = optional(number, 64) })` | `{}` | no |
| network_policy_enabled | Restrict ingress to ClickHouse and Keeper with NetworkPolicies. Needs a CNI that enforces them (for the VPC CNI, turn on its network policy agent). | `bool` | `false` | no |
| network_policy_allowed_namespaces | Namespaces whose pods may reach ClickHouse on its HTTP and native ports (and their TLS ports, with tls_enabled) when network policies are on. Pods in the installation's own namespace are always allowed. | `list(string)` | `[]` | no |
| tls_enabled | Serve the native protocol over TLS on 9440 and HTTPS on 8443, with a server certificate from cert-manager, and send distributed queries between servers over TLS. Requires cert-manager, such as from the EKS Add-ons module. Clients then trust the ca.crt in the Secret named by the tls_ca_secret_name output. | `bool` | `false` | no |
| tls_disable_plaintext_ports | With tls_enabled, close the plaintext native (9000) and HTTP (8123) ports, so every client must use TLS. The operator, probes, backups and the database job switch to the secure ports. | `bool` | `false` | no |
| tls_ca_source | Certificate authority that issues the server certificate. `self_signed` creates a CA in the namespace; `issuer` uses an existing cert-manager Issuer or ClusterIssuer, such as an AWS Private CA issuer; `secret` uses an existing CA key pair Secret in the namespace. | `string` | `"self_signed"` | no |
| tls_issuer | Existing issuer for tls_ca_source = issuer. It must put the CA in the certificate Secret's ca.crt. For AWS Private CA through aws-privateca-issuer, use kind AWSPCAClusterIssuer or AWSPCAIssuer and group awspca.cert-manager.io. | `object({ name = string kind = optional(string, "ClusterIssuer") group = optional(string, "cert-manager.io") })` | `null` | no |
| tls_ca_secret_name | For tls_ca_source = secret: a kubernetes.io/tls Secret in the namespace holding the CA certificate (tls.crt) and its private key (tls.key). | `string` | `null` | no |
| tls_extra_dns_names | More names for the server certificate, such as a DNS name you point at a load balancer. The Service, every replica's pod and localhost are always included. | `list(string)` | `[]` | no |
| database_name | Database to create on every server and to scope the writer and reader users to. Null creates none and grants on every database. | `string` | `null` | no |
| database_engine | Engine for database_name. Replicated replicates table DDL to every replica on its own; Atomic needs ON CLUSTER in every DDL statement. | `string` | `"Replicated"` | no |
| secrets_name_prefix | Prefix for the Secrets Manager secrets holding each user's credentials (<prefix>/admin, /writer, /reader, /operator). Null uses clickhouse/<cluster name>/<namespace>/<name>. | `string` | `null` | no |
| secrets_kms_key_arn | KMS key to encrypt the credential secrets with. Null uses the AWS managed key. The External Secrets Operator's role needs kms:Decrypt on it. | `string` | `null` | no |
| secrets_recovery_window_in_days | Days Secrets Manager keeps a deleted credential secret recoverable. 0 deletes it at once, which lets the same name be reused right away. | `number` | `7` | no |
| password_version | Bump to generate new passwords for every user. ClickHouse and the operator restart to pick them up, and clients must read the new secret values. | `number` | `1` | no |
| external_secrets | How the External Secrets Operator reads the credentials. With no cluster_secret_store_name the module creates a namespaced SecretStore that uses the operator controller's own AWS credentials. | `object({ cluster_secret_store_name = optional(string) refresh_interval = optional(string, "1h") })` | `{}` | no |
| reader_limits | Ceilings for the reader user. The reader may lower them per query but never raise or remove them. | `object({ max_execution_time_seconds = optional(number, 60) max_memory_usage_mib = optional(number, 4096) max_concurrent_queries = optional(number, 20) })` | `{}` | no |
| s3_bucket_creation_enabled | Create the S3 bucket for backups and the cold tier. Turn off to use an existing bucket named in s3_bucket_name. | `bool` | `true` | no |
| s3_bucket_name | Name for the new bucket (null generates one from name), or the existing bucket to use when creation is off. | `string` | `null` | no |
| s3_kms_key_arn | KMS key for the bucket's default encryption. Null uses SSE-S3. The ClickHouse role is granted use of the key. | `string` | `null` | no |
| s3_noncurrent_version_expiration_days | Days the created bucket keeps overwritten or deleted object versions before expiring them. | `number` | `30` | no |
| s3_force_destroy | Let destroying the module delete the created bucket with every backup and cold part in it. | `bool` | `false` | no |
| backup_enabled | Back up every shard to S3 on a schedule with clickhouse-backup. | `bool` | `true` | no |
| backup_schedule | Cron schedule for backups, in UTC. | `string` | `"0 3 * * *"` | no |
| backup_retention_count | Backups kept in S3 per shard. Older ones are deleted after each successful upload. | `number` | `7` | no |
| backup_image | clickhouse-backup image, including its tag. | `string` | `"altinity/clickhouse-backup:2.8.2"` | no |
| backup_resources | Requests and limits for the clickhouse-backup sidecar in each ClickHouse pod. | `object({ cpu_request = optional(string, "100m") memory_request = optional(string, "256Mi") memory_limit = optional(string, "1Gi") })` | `{}` | no |
| backup_job_image | Image the scheduled backup job runs to call each shard's clickhouse-backup API. Needs sh and curl. | `string` | `"curlimages/curl:8.22.0"` | no |
| cold_storage_enabled | Add an S3-backed `tiered` storage policy whose `cold` volume a table's TTL can move old parts to. | `bool` | `true` | no |
| cold_storage_cache_size | Local cache for reads from the cold tier, on each server's data volume. | `string` | `"10Gi"` | no |
| metrics_pod_monitors_enabled | Create Prometheus Operator PodMonitors for ClickHouse, Keeper and the operator. Needs the monitoring.coreos.com CRDs. | `bool` | `false` | no |
| metrics_pod_monitor_labels | Extra labels on the PodMonitors, for a Prometheus that selects monitors by label. | `map(string)` | `{}` | no |
| metrics_otlp_endpoint | OTLP/HTTP base URL to push ClickHouse, Keeper and operator metrics to, through a small OpenTelemetry collector the module runs. Null runs none. | `string` | `null` | no |
| metrics_otlp_interval | How often the collector scrapes before pushing over OTLP. | `string` | `"60s"` | no |
| metrics_otlp_collector_image | OpenTelemetry Collector Contrib image for the OTLP metrics push. | `string` | `"otel/opentelemetry-collector-contrib:0.161.0"` | no |
| helm_timeout_seconds | How long each Helm release may take, including the operator rolling out ClickHouse and the database creation job. | `number` | `1800` | no |

## Outputs

| Name | Description |
|------|-------------|
| host | In-cluster DNS name of the Service in front of every ClickHouse server. |
| http_port | ClickHouse HTTP interface port (null when tls_disable_plaintext_ports closes it). |
| native_port | ClickHouse native protocol port (null when tls_disable_plaintext_ports closes it). |
| http_endpoint | In-cluster URL of the HTTP interface (null when tls_disable_plaintext_ports closes it). |
| https_port | ClickHouse HTTPS interface port (null when TLS is off). |
| secure_native_port | ClickHouse native protocol port over TLS (null when TLS is off). |
| https_endpoint | In-cluster URL of the HTTPS interface (null when TLS is off). |
| cluster | Name of the ClickHouse cluster, for ON CLUSTER and the cluster() table function. |
| database | The database the module created, or null. |
| namespace | Namespace ClickHouse runs in. |
| installation_name | Name of the ClickHouseInstallation resource. |
| tls_enabled | Whether ClickHouse serves TLS on 9440 and 8443. |
| tls_server_name | Name clients verify the server certificate against (null when TLS is off). |
| tls_ca_secret_name | Kubernetes Secret in the namespace whose ca.crt is the CA clients trust, whichever CA issued it (null when TLS is off). Copy only ca.crt to clients: the Secret also holds the server's private key. |
| tls_ca_source | Certificate authority behind the server certificate: self_signed, issuer or secret (null when TLS is off). |
| tls_issuer | cert-manager issuer that signs the server certificate, as {name, kind, group} (null when TLS is off). |
| admin_secret_arn | Secrets Manager secret with the admin user's username, password and connection details. |
| writer_secret_arn | Secrets Manager secret with the writer user's username, password and connection details. |
| reader_secret_arn | Secrets Manager secret with the reader user's username, password and connection details. |
| admin_kubernetes_secret_name | Kubernetes Secret in the namespace with the admin user's credentials. |
| writer_kubernetes_secret_name | Kubernetes Secret in the namespace with the writer user's credentials. |
| reader_kubernetes_secret_name | Kubernetes Secret in the namespace with the reader user's credentials. |
| s3_bucket_name | Bucket holding backups and the cold tier, or null when neither is on. |
| s3_bucket_arn | ARN of the bucket holding backups and the cold tier, or null. |
| iam_role_arn | IAM role the ClickHouse pods use for S3 through EKS Pod Identity, or null. |
| backup_enabled | Whether scheduled backups run. |
| cold_storage_policy | Storage policy whose cold volume is S3, or null when the cold tier is off. |
