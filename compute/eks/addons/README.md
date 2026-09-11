# EKS Add-ons

Selectable add-ons for an existing EKS cluster, each toggled independently:

| Add-on | Toggle | Default | What it creates |
|---|---|---|---|
| **Karpenter** | `karpenter_enabled` | `true` | Controller + node IAM roles, Pod Identity association, instance profile, EKS access entry, SQS interruption queue, EventBridge rules (via `modules/eks_karpenter`), plus the `karpenter-crd` and `karpenter` Helm charts and an optional default NodePool |
| **AWS Load Balancer Controller** | automatic with any load balancer, or `aws_load_balancer_controller_enabled` opt-in | `false` | `aws-load-balancer-controller` Helm chart wired to the Pod Identity role created by the `compute/eks` composite; registers workload pods into shared load balancer target groups (`TargetGroupBinding`); Ingress → ALB, LoadBalancer Service → NLB |
| **External Secrets Operator** | `eso_enabled` | `true` | `external-secrets` Helm chart + Pod Identity role scoped to Secrets Manager / Parameter Store reads, plus the cluster-scoped `ravion-aws` and `ravion-aws-parameter-store` `ClusterSecretStore`s |
| **EBS CSI driver** | `ebs_csi_driver_enabled` | `false` | `aws-ebs-csi-driver` EKS add-on + Pod Identity role |
| **Workload logs** | `logs_providers` | `["loki"]` | Per destination. `loki`: an S3 bucket with a retention lifecycle rule, a Pod Identity role scoped to it, Loki in single-binary mode, and Grafana Alloy as a collection DaemonSet. `cloudwatch` and every vendor: an OpenTelemetry contrib DaemonSet with one exporter each. `[]` installs nothing |
| **Workload metrics** | `metrics_providers` | `["amp"]` | Per destination. `amp`: an Amazon Managed Prometheus workspace, a Pod Identity role scoped to `aps:RemoteWrite` on it, `kube-state-metrics`, and an OpenTelemetry collector scraping a curated allow-list. Vendors: one more exporter on the same collector. `cloudwatch`: the `amazon-cloudwatch-observability` add-on. `[]` installs nothing |
| **CloudWatch (Container Insights)** | `cloudwatch` in either provider list | not selected | `amazon-cloudwatch-observability` EKS add-on + Pod Identity role, with **Auto-Monitor off**: the Fluent Bit half only when it is a logs destination, the metrics agent only when it is a metrics destination |
| **Vendor credentials** | any vendor provider | not selected | One `ExternalSecret` per vendor (local `charts/observability-secrets`), materializing a Secrets Manager secret into a Kubernetes Secret the collectors read as environment variables |
| **Grafana read role** | `grafana_role_creation_enabled` | `false` | An IAM role trusted by `grafana.amazonaws.com` with query access to the AMP workspace — for Amazon Managed Grafana, which can read metrics but cannot reach in-cluster Loki |
| **In-cluster Grafana** | `grafana_enabled` | `false` | A Grafana release preprovisioned with both datasources: AMP over SigV4 (with its own Pod Identity role) and the in-cluster Loki |
| **Ravion Operator** | `ravion_operator_enabled` | `false` | Enrolls the cluster, stores its credential and installs the public `operator` chart. Supports optional digest-pinned executor Jobs, HA coordinators and explicit full-cluster management. |
| **Shared load balancers** | `public_alb_creation_enabled`, `private_alb_creation_enabled`, `public_nlb_creation_enabled`, `private_nlb_creation_enabled` | `false` | Terraform-managed ALBs/NLBs (via `networking/alb` and `networking/nlb`) that workloads attach to with the load balancer controller's `TargetGroupBinding` CRD, plus cluster security group ingress rules allowing each load balancer to reach pods |

The [`compute/eks`](..) composite intentionally creates none of these, so clusters only carry what they use. EBS CSI and Container Insights are native EKS add-ons installed purely through the AWS API. Karpenter, the AWS Load Balancer Controller, the External Secrets Operator, Ravion Operator, and the metrics and logs pipelines additionally install Helm charts, which are the only parts that need Kubernetes API connectivity.

> **Connectivity contract (Helm add-ons only):** the machine running Terraform must be able to reach the cluster's Kubernetes API endpoint. For private-endpoint clusters, run inside the cluster VPC with the composite's Ravion Runner security group (`ravion_runner_security_group_id` output) attached, and have the AWS CLI on PATH for `aws eks get-token`. With `karpenter_enabled`, `eso_enabled`, `aws_load_balancer_controller_enabled`, `ravion_operator_enabled`, and all four load balancer creation toggles off, no cluster connectivity is needed. `ravion_operator_enabled` additionally requires reachability to the Ravion API from the Terraform runner, because the `ravion` provider mints the agent's credential during the run — but nothing beyond the provider binary: no `curl`, no API-token input.
>
> **Authentication:** set `ravion_runner_role_arn` to the cluster's Ravion Runner role (`ravion_runner_role_arn` output of `compute/eks`) and `aws eks get-token` assumes it — the cluster module registers that role as an EKS access entry with cluster-admin, so per-run pipeline roles never need their own access entries. When null, the identity running Terraform is used directly and must already have cluster access.

Karpenter node roles do not grant Systems Manager access by default. Upgrading
detaches the previously default `AmazonSSMManagedInstanceCore` policy without
replacing nodes, unless explicitly included in
`karpenter_node_role_additional_managed_policy_arns`.

## Usage

```hcl
module "eks_addons" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks/addons?ref=main"

  cluster_name = module.eks.cluster_name
  region       = "us-east-2"

  # Karpenter (default on) needs node placement wiring and cluster access
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_subnet_ids           = module.eks.node_subnet_ids
  ravion_runner_role_arn    = module.eks.ravion_runner_role_arn

  ebs_csi_driver_enabled = true

  # External Secrets Operator (default on) — narrow the read scope from
  # "everything in this account and region" to one prefix
  eso_secret_and_parameter_arns = ["arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/*"]

  # Workload metrics into Amazon Managed Prometheus. Creates the workspace and
  # installs the collector.
  metrics_providers = ["amp"]

  # Workload logs into an in-cluster Loki backed by S3 in this account.
  logs_providers     = ["loki"]
  log_retention_days = 30

  # Shared public ALB that web workloads bind to via TargetGroupBinding
  public_alb_creation_enabled = true
  public_alb_https_enabled    = true
  public_alb_certificate_arns = [aws_acm_certificate.main.arn]
  public_subnet_ids           = module.network.public_subnet_ids
}
```

> **Pinning a `ref`:** this repository has no `vX.Y.Z` tags. Releases are tagged
> per module definition as `rvn-<definition-type>@<x.y.z>` (for example
> `rvn-aws-network@1.0.1`). Once a release of this stack is cut, pin to
> `?ref=rvn-eks-addons@<x.y.z>`; until then use `?ref=main` or a commit SHA.

## Ravion Operator Terraform names

Every Terraform variable and output previously prefixed with `beacon_` now uses
the equivalent `ravion_operator_` name. Update direct module calls and any
Advanced Terraform variables before upgrading. Ravion form fields already use
the new names, so module instances configured through the form need no input
changes.

Terraform resource labels were renamed as well. Included `moved` blocks preserve
the Secrets Manager and Helm resource addresses; that address rename alone does
not recreate them. The Helm release remains `ravion-beacon`; explicit chart name
overrides preserve its resource names and immutable Deployment selectors. The chart
now comes from `oci://public.ecr.aws/a8z1i1r2/operator`, and the default connection
path is `/operator/v1/connect`. Credential Secret and Secrets Manager paths retain
their existing names.

### Namespace migration

The default `ravion_operator_namespace` is now **`ravion-operator`**. Shared
observability components follow this default unless their namespace is explicitly
overridden. Moving existing releases from `ravion-beacon` requires Helm release
replacement, including the credential Secret release. The API credential and AWS
Secrets Manager mirror do not need replacement just to change namespaces.

Expect a logs/metrics interruption while the old releases are removed and the new
ones start. Namespace changes **do not migrate PVCs or local data**: inspect and
back up persistent volumes before applying. The existing Loki S3 bucket and AMP
workspace remain unchanged. Review the fresh plan for expected Helm replacements;
a namespace migration is not a no-destroy plan.
Keep `ravion_operator_namespace = "ravion-beacon"` explicitly to defer the move.

### Workload namespace bootstrap

Apply creates missing deployment and observation namespaces before installing
the Operator's namespaced Roles and RoleBindings. For example,
`ravion_operator_deploy_namespaces = ["rvn-app"]` now works on a fresh cluster.
This does not give the Operator namespace-creation permissions.

A separate `ravion-operator-namespaces` Helm release in `kube-system` owns only
namespaces it creates. Existing namespaces are reused without changing ownership.
Created namespaces carry Helm's `keep` policy: removing a namespace from the list,
disabling Operator, or uninstalling add-ons leaves that namespace and its workloads
in place. Namespace deletion remains an explicit administrative operation. Set
`ravion_operator_namespaces_creation_enabled = false` when another stack provisions
all scoped namespaces. Raw Helm values that override scope must be kept in sync
with the Terraform namespace inputs used for bootstrap.

### Shared load balancers

The shared load balancers mirror the ECS Cluster module's pattern: one Terraform-managed ALB (or NLB) is shared by many workloads. A workload module creates its own target group and listener rule, then registers pods with the target group in-cluster via the AWS Load Balancer Controller's [`TargetGroupBinding`](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/targetgroupbinding/targetgroupbinding/) CRD — enabling any load balancer therefore installs the controller automatically.

Placement and security wiring:

- Public ALB/NLB launch into `public_subnet_ids` (required when either public load balancer is enabled).
- Private ALB/NLB launch into `node_subnet_ids`.
- Each load balancer's security group is granted ingress to `cluster_security_group_id` on all TCP ports, so registered pods are reachable on any container port.

### Secrets (External Secrets Operator)

Kubernetes has no equivalent of the ECS task definition's `valueFrom` injection, so this add-on installs the [External Secrets Operator](https://external-secrets.io/) as the bridge. Workloads reference a Secrets Manager secret or SSM parameter **by ARN**; the operator reads it with its own Pod Identity credentials and materializes it into a Kubernetes Secret in the workload's namespace. Secret values never pass through Terraform state, Helm values, or Helm release history.

**Contract for workload charts.** The stores are cluster-scoped, so a chart in any namespace references them by name with no per-namespace setup:

| Backend | `secretStoreRef.name` | `secretStoreRef.kind` | `apiVersion` |
|---|---|---|---|
| AWS Secrets Manager | `ravion-aws` (`eso_secrets_manager_store_name`) | `ClusterSecretStore` | `external-secrets.io/v1` |
| AWS SSM Parameter Store | `ravion-aws-parameter-store` (`eso_parameter_store_store_name`) | `ClusterSecretStore` | `external-secrets.io/v1` |

There are two stores because ESO's AWS provider takes a single `service` per store — Secrets Manager and Parameter Store cannot share one. `ravion-aws` is the Secrets Manager store, which is the name Ravion app charts default to; charts select the Parameter Store variant only for `ssm` references. Both names are outputs (`eso_secrets_manager_store_name`, `eso_parameter_store_store_name`), so charts should read them rather than hardcode.

A workload's `ExternalSecret` then looks like:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-service
spec:
  secretStoreRef:
    name: ravion-aws
    kind: ClusterSecretStore
  target:
    name: my-service-env
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/db-AbCdEf
        property: password # optional JSON-key extraction, ECS `::jsonkey::` parity
```

**IAM scoping.** The operator's Pod Identity role grants `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret`, `ssm:GetParameter`, and `ssm:GetParameters`. Because workload secrets are created long after this stack applies, the default resource scope is every secret and parameter **in this account and region**. Set `eso_secret_and_parameter_arns` to narrow it to specific ARNs or prefixes — or to reach other regions and accounts, which the default deliberately excludes. Secrets encrypted with a customer-managed KMS key additionally need that key listed in `eso_kms_key_arns`; the AWS-managed `aws/secretsmanager` and `aws/ssm` keys need no explicit grant.

**At rest.** The values themselves live only in AWS Secrets Manager / Parameter Store, encrypted with KMS there. The Kubernetes Secrets the operator materializes are stored in etcd under **KMS envelope encryption**, which the [`compute/eks`](..) cluster module enables by default (`secrets_encryption_enabled`, `true`, creating a dedicated CMK per cluster unless `secrets_kms_key_arn` is supplied). Materialized Secrets are still readable by anything with Secret read RBAC in that namespace; mounting values as files via the [AWS Secrets Store CSI driver](https://github.com/aws/secrets-store-csi-driver-provider-aws), which skips the Kubernetes Secret object entirely, is a future hardening option not implemented here.

### Logs and metrics providers

Each signal is one multi-select. **Loki and Amazon Managed Prometheus are the defaults**, so a cluster that touches nothing renders both dashboard tabs; nothing CloudWatch is installed by default or as a side effect of anything else. Add as many destinations as you like per signal — the collectors fan out, so a log file is tailed once and the cluster scraped once however many copies leave it.

| `logs_providers` | Collector | Destination | In Ravion |
|---|---|---|---|
| `loki` *(default)* | Alloy DaemonSet | In-cluster Loki, chunks in an S3 bucket in your account | **Renders**, through Ravion Operator |
| `cloudwatch` | OpenTelemetry DaemonSet (`awscloudwatchlogs`) | Log group `/ravion/eks/<cluster>`, one stream per pod as `<namespace>/<pod>/<container>` | **Renders**, and is the fallback when the in-cluster agent is offline |
| `grafana_cloud` | Alloy (`loki.write` with basic auth) | Your Grafana Cloud Loki endpoint | Ships + "Open in Grafana Cloud" |
| `datadog` | OpenTelemetry (`datadog`) | Datadog intake for the chosen site | Ships + "Open in Datadog" |
| `new_relic` | OpenTelemetry (`otlphttp`) | New Relic OTLP, US or EU | Ships + "Open in New Relic" |
| `opensearch` | OpenTelemetry (`opensearch`, SigV4) | An Amazon OpenSearch Service domain | Ships + "Open Dashboards" |
| `splunk` | OpenTelemetry (`splunk_hec`) | Splunk HTTP Event Collector | Ships |
| `otlp` | OpenTelemetry (`otlphttp`) | Any OTLP/HTTP receiver | Ships |

| `metrics_providers` | Exporter | Destination | In Ravion |
|---|---|---|---|
| `amp` *(default)* | `prometheusremotewrite` + SigV4 | Amazon Managed Prometheus workspace in your account | **Renders** |
| `prometheus` | `prometheusremotewrite` | Prometheus in your cluster, PV-backed | **Renders**, through Ravion Operator, behind AMP |
| `cloudwatch` | the CloudWatch agent (add-on) | `ContainerInsights` metric namespace | **Renders**, last in the chain |
| `grafana_cloud` | `prometheusremotewrite` + basic auth | Grafana Cloud Prometheus remote write | Ships + link |
| `datadog` | `datadog` | Datadog intake | Ships + link |
| `new_relic` | `otlphttp` | New Relic OTLP | Ships + link |
| `otlp` | `otlphttp` | Any OTLP/HTTP receiver | Ships |

**Several rendering providers are a fallback chain, never a merge.** `logs_rendering_providers` and `metrics_rendering_providers` publish the selected members of a fixed order — logs `loki → cloudwatch`, metrics `amp → prometheus → cloudwatch` — and the dashboard reads the first store that can answer right now, saying which one it is showing. That turns the in-cluster store's one weakness (no agent, no logs) into a soft failure rather than an empty tab. Merging two stores for the same workload would show every line twice, so it is deliberately not done.

**Cost is a choice the form makes visible.** The in-cluster store costs S3 storage and requests plus the collector pods, with no per-gigabyte ingest. AMP bills per sample (roughly $25–50/month for a 20-service cluster). CloudWatch Logs bills per gigabyte ingested and then stored; Container Insights bills per metric. Every vendor bills for what it receives, so two ship-only destinations is two bills for the same lines — by selection, never by accident.

**Vendor credentials never pass through Ravion.** Every key is a Secrets Manager ARN. The External Secrets Operator this module installs reads it with its own Pod Identity role and materializes a Kubernetes Secret in the collector namespace; the collectors read it as an environment variable, and the value appears in no Helm value, no Terraform output, and no release history. Selecting a vendor with `eso_enabled = false` fails the plan rather than installing a collector that cannot authenticate.

**Amazon OpenSearch Service authenticates with an IAM role, not a key.** The collector signs its requests with its Pod Identity role, published as `logs_opensearch_role_arn`; the domain's own access policy or fine-grained role mapping has to name that role, and this module cannot write it because it does not manage the domain. The IAM half it does write is scoped to `es:ESHttp*` on the account's domains in this region.

**In-cluster Prometheus is a store, not a scraper.** Every scrape in this module belongs to the one collector, which owns the curated allow-list and the label contract; the Prometheus this provider installs runs with `web.enable-remote-write-receiver`, no scrape jobs, no alertmanager, no pushgateway and no second copy of the exporters already running. It needs a `StorageClass` for its PersistentVolume (`ebs_csi_driver_enabled` on a Ravion cluster). `metrics_prometheus.endpoint` points at a Prometheus you already run and skips the install entirely. Like Loki, it has no ingress: Ravion reads it through Ravion Operator, whose allowlist this module writes.

**Which collector runs.** Alloy carries the loki-family destinations (`loki`, `grafana_cloud`) because Ravion's log views are written against its label contract; the OpenTelemetry contrib DaemonSet carries the rest. A default cluster runs Alloy alone; a CloudWatch-only cluster runs the OpenTelemetry collector alone; a cluster with both runs both, each reading the same files once. `logs_excluded_namespaces` (default `kube-system`, `kube-node-lease`, `amazon-cloudwatch`, `ravion-operator`, `ravion-beacon`) keeps a namespace out of both, including the legacy namespace during migration.

**Migration from 0.7.x.** `logs_enabled`, `metrics_enabled` and `cloudwatch_observability_enabled` were read as fallbacks in 0.8.0 and 0.8.1, and are **removed in 0.8.2** — an instance still on 0.7.x should pass through 0.8.1, which maps them onto the lists:

| Before | After the upgrade |
|---|---|
| `logs_enabled = true` | `logs_providers = ["loki"]` — same pipeline, same bucket, same endpoint |
| `logs_enabled = false` | `logs_providers = []` — stays off; it does not adopt the new default |
| `metrics_enabled = true` | `metrics_providers = ["amp"]` |
| `cloudwatch_observability_enabled = true` | `cloudwatch` appended to `metrics_providers`, so `[amp, cloudwatch]`: AMP renders, Container Insights is the fallback |

The one behavioural change on upgrade is that the CloudWatch add-on is re-applied with **Auto-Monitor off**, so agents previously injected into workloads leave them on their next rollout. Anyone who actually wanted Application Signals turns its toggle on.

### Workload metrics (Amazon Managed Prometheus)

`amp` in `metrics_providers` (the default) turns on a Prometheus pipeline that lives entirely in the customer's account: an [Amazon Managed Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html) workspace, `kube-state-metrics`, and a single-replica OpenTelemetry collector running the [AWS Distro for OpenTelemetry](https://aws-otel.github.io/) image. The collector scrapes three targets, drops everything outside a curated allow-list, and remote-writes the rest to the workspace signed with SigV4.

| Target | Reached via | What it contributes |
|---|---|---|
| cAdvisor (`/metrics/cadvisor`) | kubelet, through the **API server proxy** (`/api/v1/nodes/<node>/proxy/...`) | Per-container CPU, throttling, memory, network, OOM kills |
| `kube-state-metrics` | in-cluster Service | Desired vs. actual replicas, pod phase, restart and termination reasons, HPA state, node conditions and capacity |
| kubelet `/metrics/resource` | kubelet, through the API server proxy | Node CPU and memory headline numbers |

Scraping through the API server proxy rather than each node's port 10250 is what makes this work on private-endpoint clusters and behind restrictive node security groups: the collector needs a network path to the Kubernetes API and nothing else. The cost is `nodes/proxy` in its ClusterRole, which is the only permission beyond reading the node list.

There is deliberately **no node-exporter**: node capacity comes from `kube_node_status_capacity` and node usage from the kubelet, which covers the curated set without a DaemonSet on every node.

**The allow-list is the design.** AMP bills per sample ingested, and an unfiltered Kubernetes cluster produces tens of thousands of series. The collector keeps ~8 cAdvisor families, ~24 kube-state families, and 2 kubelet families — roughly 75 series per pod — with a `keep` action in `metric_relabel_configs`, which runs *before* samples enter collector memory. cAdvisor's `id`, `name` and `image` labels are dropped (they change on every restart and nobody queries them), and cAdvisor's pod-level aggregate rows — the ones with an empty `container` label — are dropped for the CPU, memory and OOM families, but **kept** for the network families, which only exist on those rows.

The base list lives in `locals.tf`. Widen it with `metrics_additional_allowlist`, whose entries are appended to every scrape job:

```hcl
metrics_enabled              = true
metrics_additional_allowlist = ["my_app_requests_total", "my_app_.*_seconds"]
```

Prometheus anchors relabel regexes at both ends, so each entry must match a **whole** metric name: `my_app_.*`, never `.*my_app.*`.

**Cost levers, in order of effect:** `scrape_interval_seconds` (default `60`; sample count scales inversely), the allow-list, and the number of pods. Expect roughly $25–50/month for a 20-service cluster and $150–250/month for 100 services with the curated set.

**The workspace.** One per cluster, aliased `ravion-<cluster_name>`. Set `amp_workspace_id` to bring an existing one instead — for sharing a workspace across clusters, or for reaching one that already exists. `amp_region` puts the workspace (or points remote write at one) in a different region than the cluster, which is the answer for regions where AMP is not offered: remote write works cross-region, at the cost of inter-region data transfer. AMP's regional availability is not validated by this module, because a static region list rots faster than it helps.

**Identity.** The collector's service account is bound by EKS Pod Identity to a role whose only permission is `aps:RemoteWrite` on that single workspace ARN. The `sigv4auth` extension configures no credentials of its own — it signs with whatever the AWS SDK default credential chain resolves, which the Pod Identity Agent populates.

**Namespace.** The metrics components share Ravion Operator's namespace (`ravion_operator_namespace`, default `ravion-operator`), so Ravion's in-cluster components live in one place. `metrics_namespace` splits them if that is not wanted.

**Sizing.** One collector Deployment scrapes every node, which is comfortable to roughly 100 nodes at a 60-second interval. Past that, the escape hatch is the chart's target allocator with a StatefulSet — deliberately not in this release. `otel_collector_resources` defaults to requests of `100m` / `256Mi` and a memory limit of `512Mi`; the limit matters because the collector's `memory_limiter` processor sizes itself as a percentage of the container limit, and with no limit it would measure against the whole node.

### Workload logs (Loki on S3)

`loki` in `logs_providers` (the default) turns on a log pipeline that lives entirely in the customer's account: [Grafana Alloy](https://grafana.com/docs/alloy/latest/) as a DaemonSet reading every container's stdout off its own node, [Loki](https://grafana.com/docs/loki/latest/) in the cluster indexing and serving it, and an S3 bucket holding every chunk.

**Loki is never exposed.** No ingress, no load balancer, not even the chart's nginx gateway — a ClusterIP Service on port 3100 and nothing else. Ravion reads it by asking the Ravion Operator to proxy a query over the WebSocket Ravion Operator already holds, so there is no inbound path to open, nothing to put a certificate on, and no log data leaving the account except as the answer to a query. That is also why `loki_endpoint` is an in-cluster URL: it is what Ravion Operator's proxy allowlist names, not something to publish.

#### The label set is a contract

Loki indexes labels and stores everything else. A label with many distinct values multiplies streams, and streams are what a Loki runs out of — so the collector attaches exactly three, all of them low-cardinality:

| Label | Source | Why it is safe to index |
|---|---|---|
| `namespace` | the pod's namespace | Bounded by the cluster |
| `app` | `app.kubernetes.io/name`, falling back to `app`, falling back to `workload` | One value per application |
| `workload` | the pod's controller with the ReplicaSet hash stripped | Stable across rollouts |

Severity is attached as **structured metadata** (`level`), not a label: it is stored and filterable but not indexed, so it does not split one request's lines across several streams. There is deliberately **no pod-name label** — that would turn one stream per workload into one per replica per restart — and Alloy explicitly drops the `filename` label that `loki.source.file` adds, because the path contains the pod UID and would smuggle the same cardinality back in.

**Changing these names is a breaking change** for Ravion's log views, which build LogQL selectors on them. `tests/logs.tftest.hcl` asserts the whole set for exactly that reason.

#### Retention

Two mechanisms, and they are not redundant:

- **Loki's compactor is the authority.** `log_retention_days` becomes `limits_config.retention_period`, and the compactor (`retention_enabled: true`, which is *off* in stock Loki and the single most common reason a Loki bucket grows forever) rewrites the index and deletes expired chunks. This is why Loki's IAM role carries `s3:DeleteObject`.
- **The bucket lifecycle rule is the backstop**, and expires objects **seven days later** than the compactor would. The gap is deliberate: a rule that expired on the same day could delete an index file the compactor still intends to read. It only ever sweeps up what a compactor that stopped running would have orphaned.

`loki_s3_bucket_name` brings an existing bucket instead, and the module then manages neither it nor its retention — only the compactor half applies.

#### Sizing and storage

Loki runs in **single-binary mode**: every target in one StatefulSet replica, with the memcached chunk and result caches, the gateway, the canary and the bundled MinIO all off. A simple-scalable deployment is three workloads plus two memcached tiers before it stores a byte, which is the wrong shape for a cluster running twenty services. `loki_helm_values` is the documented escape hatch for larger ones.

`loki_persistence_enabled` is **off** by default. Loki's chunks are in S3 either way; what the local volume holds is the write-ahead log, the compactor's working directory, and the index cache. With persistence off the module mounts an `emptyDir` at `/var/loki` sized by `loki_persistence_size` — necessary, not cosmetic, because the chart only mounts that path when persistence is on and the container runs with a read-only root filesystem. Turning persistence on needs a working `StorageClass`, which on a Ravion cluster means `ebs_csi_driver_enabled`; an unschedulable PVC is a worse first run than an ephemeral volume, hence the default.

#### CloudWatch is a provider, not a mode

Container Insights used to be a section of its own, defaulting to off and described as a legacy toggle. It is now `cloudwatch` in `logs_providers` and `metrics_providers`, and the add-on is installed because one of those lists names it — never as a default and never as a side effect.

Its two halves follow the two lists. `cloudwatch` in `metrics_providers` runs the CloudWatch agent (Container Insights, `cloudwatch_enhanced_observability_enabled` on by default); `cloudwatch` in `logs_providers` turns on the add-on's Fluent Bit half, which writes to `/aws/containerinsights/<cluster>/application`. Ravion's own CloudWatch log pipeline is separate and writes to `/ravion/eks/<cluster>` through the OpenTelemetry collector, with one stream per pod named `<namespace>/<pod>/<container>` — that is the group `logs_cloudwatch_log_group` publishes and the service modules query.

**Auto-Monitor is pinned off.** The add-on's admission webhook, left at its default, injects the AWS Distro for OpenTelemetry agent into *every* workload in the cluster and restarts the pods to do it — which is where a wall of `AWS Application Signals…` log noise comes from on a cluster that only asked for metrics. The module always sends `manager.applicationSignals.autoMonitor.monitorAllServices = false` unless `cloudwatch_application_signals_enabled` is set.

Application Signals with **no namespace list** is a deliberate whole-cluster opt-in and flips that switch to `true`. Application Signals **with** a namespace list keeps the cluster-wide switch off and publishes the namespaces as `cloudwatch_application_signals_namespaces`: annotate exactly those namespaces for auto-instrumentation (`instrumentation.opentelemetry.io/inject-<language>: "true"`, per the AWS Application Signals documentation for the language in use). The module does not annotate them itself, because that would mean taking Helm ownership of namespaces it did not create.

`metrics_cloudwatch.addon_configuration_values` is merged over the module's document per top-level key, for anything the add-on supports that this module does not surface.

The cluster module's Logs tab keeps the EKS control-plane group (`/aws/eks/<cluster>/cluster`), which is native to EKS and unaffected.

### Grafana

There are two Grafana stories here, and which one applies depends on whether you want to see the logs.

**Metrics only → Amazon Managed Grafana** (`grafana_role_creation_enabled`). AMG can query AMP perfectly well. The toggle creates an IAM role trusted by `grafana.amazonaws.com` with an `aws:SourceAccount` condition (this account by default, `grafana_source_account_id` to point at another) — the confused-deputy guard AWS documents for service principals. No Grafana workspace is created: provisioning one requires IAM Identity Center or SAML wiring that is organization-scoped, and putting an org-level blast radius behind a cluster-level toggle is the wrong trade.

In the workspace's *Data sources* page, add a Prometheus source with SigV4 auth:

```
Type:        Prometheus
URL:         https://aps-workspaces.<region>.amazonaws.com/workspaces/<amp_workspace_id>
SigV4 auth:  enabled
Region:      <amp_region>
Assume role: <grafana_role_arn>
```

**Metrics and logs → in-cluster Grafana** (`grafana_enabled`). AMG runs in an AWS-managed VPC and cannot reach a ClusterIP Service, so "the logs, in Grafana" is only answerable by a Grafana inside the cluster. The release is preprovisioned with both datasources — AMP over SigV4, signed with credentials the Pod Identity Agent supplies to its own role, and Loki over plain in-cluster HTTP — and a datasource whose pipeline is not installed is simply not rendered.

No ingress and no Service type beyond ClusterIP. Reach it with:

```console
kubectl -n <grafana_namespace> port-forward svc/<grafana_service> 3000:80
```

The chart generates an admin password into a Secret; `grafana_helm_values` is the route to an ingress, persistence, an existing admin secret, or dashboards. A module that quietly published a Grafana with a default password to the internet would be a bug, not a convenience.

**Self-hosted Grafana elsewhere** can reach AMP the same way AMG does, given credentials that can assume `grafana_role_arn`:

```yaml
apiVersion: 1
datasources:
  - name: ravion-amp
    type: prometheus
    access: proxy
    url: https://aps-workspaces.<region>.amazonaws.com/workspaces/<amp_workspace_id>
    jsonData:
      httpMethod: POST
      sigV4Auth: true
      sigV4AuthType: default
      sigV4Region: <amp_region>
      sigV4AssumeRoleArn: <grafana_role_arn>
```

It cannot reach Loki unless it runs in the cluster. Note that SigV4 also requires `sigv4_auth_enabled = true` under `[auth]` in `grafana.ini` — the in-cluster release sets that for you, and a datasource that asks for SigV4 without it fails to authenticate with no hint as to why.

Values for every snippet come from module outputs: `amp_query_endpoint`, `amp_region`, `amp_workspace_id`, `grafana_role_arn`, `loki_endpoint`, `grafana_namespace`, `grafana_service`.

### Ravion Operator

Ravion Operator is Ravion's in-cluster agent. It dials the control plane **outbound** over a single WebSocket — the control plane can never dial in, because a private-endpoint EKS API is reachable from nowhere else — and reports workload state. Optionally, and separately, it can perform Ravion's Helm deploys from inside the cluster.

Off by default. `ravion_operator_enabled = true` does three things in one apply:

1. **Mints** the cluster's credential with the `ravion` provider (`ravion_operator_credential`). Ravion issues a client secret on the organization's shared WorkOS M2M application server-side, records it against this cluster's Ravion Operator row, and returns a `client_id` + `client_secret` pair.
2. **Stores** that pair — in a Kubernetes `Secret` named `ravion-beacon-credential` in `ravion_operator_namespace` under the keys `clientId` and `clientSecret`, and, as a mirror, in an AWS Secrets Manager secret in *your* account (`ravion/beacon/<cluster>/credential`) carrying the same two keys.
3. **Installs** the agent chart, wired to that Secret.

```hcl
module "eks_addons" {
  # ...
  ravion_operator_enabled = true

  # Optional: bound what the agent can see to the namespaces Ravion deploys into
  ravion_operator_namespace_scope = ["app-prod", "app-stg"]
}
```

There is **no API-token input**. The `ravion` provider authenticates with `RAVION_BASE_URL` + `RAVION_API_KEY`, which a Ravion pipeline injects into the run automatically; the organization the cluster is attached to comes from the key's claims, so a key for one organization can never attach a cluster to another. Applying this module **outside** a Ravion pipeline means exporting both yourself — see [Applying outside a Ravion pipeline](#applying-outside-a-ravion-pipeline).

#### The credential, and the mirror

The client secret is minted by WorkOS and returned **exactly once**. Ravion keeps no plaintext copy, so `ravion_operator_credential` has no refresh (its `Read` is a state passthrough) and cannot be imported. **Terraform state holds the credential.**

The Secrets Manager secret is the operator's **recovery copy of what state holds** — a mirror, deliberately not an idempotency anchor. Nothing reads it back, and the module no longer asks it "has this cluster been enrolled already?"; that question belonged to the curl-era enrollment and is gone. Every argument of the resource is `RequiresReplace`, and **a create for a cluster ARN that already has an agent mints a new secret and revokes the previous one** — so there is no `409`, no destroy-first dance, and a half-failed apply is simply retryable. Rotation is `tofu apply -replace=…`; a lost state is recovered the same way, at the cost of one reconnect.

The runner needs, alongside the existing AWS-CLI-on-PATH requirement, the `ravion` provider binary and IAM permission to `secretsmanager:CreateSecret`, `GetSecretValue`, `PutSecretValue`, `DescribeSecret`, `TagResource` and `DeleteSecret` on that secret.

**The client secret is never an output.** `ravion_operator_client_id`, `ravion_operator_agent_id` and `ravion_operator_client_secret_id` are — all three are opaque identifiers the API documents as safe to expose. Note that the client id is the *shared* application's and is identical for every cluster in the organization; `ravion_operator_client_secret_id` is what distinguishes which credential a connecting agent presents.

#### Testing before the public chart exists

Two overrides, both designed for exactly this:

```hcl
# A chart directory on disk instead of the ECR Public reference. Anything that
# is not an `oci://` reference is treated as a filesystem path.
ravion_operator_chart_source = "/path/to/ravion/packages/operator/chart/operator"

# A gateway on your own machine instead of the production endpoint. Reachable
# from inside the cluster, so a tunnel or an in-cluster address, not localhost.
ravion_operator_endpoint = "ws://host.docker.internal:3001/operator/v1/connect"
```

`ravion_operator_chart_version` is ignored for a filesystem chart. Note that `ravion_operator_chart_source` must stay **publicly pullable** in production: customer clusters cannot pull from Ravion's private ECR.

Pointing credential issuance at a local control plane is no longer a module input — it is `RAVION_BASE_URL`, see below.

#### Applying outside a Ravion pipeline

Inside a Ravion pipeline there is nothing to do: the runner injects `RAVION_API_KEY` (a short-lived JWT minted for the stack run) and `RAVION_BASE_URL`, and `tofu init` resolves the provider from Ravion's registry at `providers.ravion.com`.

Running `tofu apply` by hand with `ravion_operator_enabled = true` needs both exported:

```bash
export RAVION_BASE_URL="https://api.ravion.app"   # or http://localhost:8080 against a local api-go
export RAVION_API_KEY="<Ravion API key / JWT>"
```

For an **unreleased provider build** — a change you are testing out of the monorepo — skip the registry with a `dev_overrides` block, which makes `tofu init` unnecessary for the `ravion` provider (and prints a warning on every plan, which is expected):

```hcl
# ~/.terraformrc
provider_installation {
  dev_overrides {
    "providers.ravion.com/ravion/ravion" = "/path/to/ravion/packages/terraform-provider-ravion"
  }
  direct {}
}
```

```bash
cd /path/to/ravion/packages/terraform-provider-ravion
go build -o terraform-provider-ravion
```

To exercise the real registry protocol instead of overriding it, that package's `localregistry/` serves a locally built provider as a registry.

#### Inline image updates

With `ravion_operator_self_update_enabled` on (the default), the control plane rolls each cluster's agent forward by patching Ravion Operator's own Deployment — a namespaced `Role` scoped by `resourceNames` to that one object, and the only write permission the chart creates by default. An apply that re-asserted the image tag would revert every staged rollout, so this module passes **no tag at all** by default and the chart (0.4.1+, `image.preserveOnUpgrade`) reads the image the release is already running back on every `helm upgrade` and re-emits it — registry and tag — once that release's rollout has settled. A fresh install starts at the chart's `appVersion` (the floor); every later apply leaves the version with whoever set it last. A release whose last rollout wedged is deliberately *not* preserved: the chart falls back to its floor, so a plain re-apply repairs it instead of re-asserting the image that could not start.

`ravion_operator_image_tag` is the one deliberate exception, and it is a **pin**:

- **While it is set, every apply asserts it** — including over a control-plane rollout that happened in between. Use it to hold a cluster at a version, on purpose.
- **Removing it hands the version back to the control plane** on the next apply: the chart is rendered with no tag and preserves whatever is running.
- Releases up to 0.8.3 instead ignored the tag after its first apply (`ignore_changes = [set]`), which froze the first tag ever applied into the state for good; an instance created back then may still carry the legacy `beacon_image_tag` (and an `image.repository` override in `beacon_helm_values`) in its advanced variables from a registry that no longer holds that tag. Remove both when upgrading.
- **To make Terraform the single owner of the version instead**, set `ravion_operator_self_update_enabled = false` and pin `ravion_operator_image_tag`. You then own keeping the agent current — Ravion supports two agent minor versions back.
- The running version is reported in every heartbeat, so a cluster stuck on an old build is visible in fleet health rather than discovered during an incident.

#### Namespace scoping and the deploy grant

`ravion_operator_namespace_scope` is the one value that turns a cluster-wide component into a bounded one, and it is enforced by Kubernetes rather than by the agent: non-empty renders **no observation ClusterRole at all**, one namespaced `Role`/`RoleBinding` per entry instead. A scoped install can read no `nodes` and no `namespaces`, so the node count in fleet health is reported as unknown; nothing else changes.

`ravion_operator_deploy_enabled` permits workload writes in `ravion_operator_deploy_namespaces`, falling back to `ravion_operator_namespace_scope`. This default scope excludes RBAC, namespaces and cluster-scoped resources. If both lists are empty, apply fails unless full management is explicitly enabled.

#### Durable executor Jobs and HA

The Ravion form exposes only **Ravion EKS Management** for Operator. Durable
executor Jobs and workload namespace bootstrap are enabled automatically;
customization uses **Advanced Terraform variables**. The module automatically pins chart
`0.4.1-ci.cd73ca0f0647`, whose package bundles the matching verified multiarch image
digest, and enables adaptive HA and full-cluster management with Jobs. Job mode
disables self-update. Direct Terraform callers opt in with
`ravion_operator_execution_jobs_enabled = true`.

Direct Terraform callers select a chart from a successful Operator publishing run. Leave the execution image empty to use its bundled digest, or override it with a matching digest-qualified `image_ref`. Publication must finish before applying addons; an unpublished source chart requires an explicit digest.

```hcl
ravion_operator_enabled                = true
ravion_operator_deploy_enabled         = true
ravion_operator_deploy_namespaces      = ["app-prod"]
ravion_operator_execution_jobs_enabled = true
ravion_operator_chart_version          = "0.4.1-ci.cd73ca0f0647"
ravion_operator_coordinator_enabled    = true
```

Job mode disables self-update in both the enrolled capability and the Helm values. The chart uses the execution image for **both coordinators and executors**, overriding live-image preservation; an inline image-tag pin is rejected. The stable enrollment ID is passed as `cluster.installationId` and exposed as `ravion_operator_installation_id`.

HA defaults to adaptive sizing and requires a replica-aware gateway and a matching adaptive-capable Operator image/chart. One eligible node runs one coordinator, two run two, and three or more run three with the default cap. The elected coordinator checks Ready, uncordoned nodes and placement constraints every 30 seconds; decreases require two minutes of a stable target. Helm leaves the runtime replica count to Operator. Single-node clusters work without node-level redundancy. Set `ravion_operator_coordinator_adaptive_enabled=false` for fixed sizing, namespace-scoped observation, or custom affinity; `ravion_operator_coordinator_replicas` is a maximum in adaptive mode and a fixed count otherwise.

Each coordinator requests 500m CPU/1Gi memory and limits at 2 CPU/2Gi. Each executor requests 1 CPU/2Gi memory/1Gi ephemeral storage and limits at 4 CPU/8Gi/20Gi. Nodes still need enough free resources to schedule the pods; resource overrides use `coordinator.resources` and `executionJobs.resources` in `ravion_operator_helm_values`.

Drain inline deployments and remediation before enabling Jobs. Drain durable executions before changing execution mode, management scope or retained capacity. Preserve the Operator namespace, `rvn-installation` identity, execution records and ownership/capacity Leases during migration. Missing workers or an uncertain mutation are not permission to delete ownership and launch a competing writer.

The Ravion form enables **full-cluster management** by default with Jobs. Direct Terraform callers enable `ravion_operator_full_management_enabled` and leave both observation and deployment namespace lists empty. This grants wildcard Kubernetes RBAC for CRDs, RBAC, namespaces, custom resources and workloads, using one installation-wide mutation lane. Null executor capacity automatically selects 1 for full management or 4 for namespace-scoped Jobs (up to 64 with an override). Capacity limits admission; it does not provision nodes or ensure pods can be scheduled.

To restrict a Ravion installation, use **Advanced Terraform variables**:

```hcl
ravion_operator_full_management_enabled = false
ravion_operator_deploy_namespaces       = ["app-prod"]
```

Namespace-scoped observation additionally requires `ravion_operator_coordinator_adaptive_enabled = false`. Existing form-level execution mode, namespace bootstrap, image, chart, scope and HA choices are replaced by managed defaults; preserve custom settings through advanced overrides before upgrading. Existing retained capacity must be preserved explicitly or migrated after draining executions.

To use legacy inline execution, set these advanced overrides together:

```hcl
ravion_operator_execution_jobs_enabled  = false
ravion_operator_full_management_enabled = false
ravion_operator_coordinator_enabled     = false
ravion_operator_deploy_namespaces       = ["app-prod"]
```

Set `ravion_operator_namespaces_creation_enabled = false` to disable Terraform
workload namespace bootstrap. Inline self-update can be disabled with
`ravion_operator_self_update_enabled = false`.

The web, worker and cron modules continue to submit their existing Git-sourced Helm definitions through `aws:eks`. The control plane selects the eligible Operator enrolled for the cluster ARN and packages the chart for it. No new deployment discriminator or installation-ID field is supported in that module deploy schema. Provider-neutral prepared deployments are a separate API path, not yet a general-purpose module deployment type.

Values this module does not surface directly — `portForward.enabled`, `helmInventory.enabled`, `redaction.extraPatterns`, `image.repository`, resources, tolerations — go through `ravion_operator_helm_values`. Read the chart's `README.md` before enabling any of the opt-in capabilities.

The Ravion form uses **Ravion EKS Management** to control both Operator installation and deployments; the deployment flag follows the management toggle, including upgrades from a separately disabled deployments flag. Image/chart selection, executor Jobs, namespace bootstrap, adaptive HA and full management are automatic. Execution mode, namespace bootstrap, inline self-update, image/chart, scope, HA, capacity and Helm customization are available through **Advanced Terraform variables**.

#### Rotating and revoking

Rotation is now **replacement of the credential resource** — the control plane revokes the outgoing secret as it mints the new one, and the same apply rewrites both the Kubernetes Secret and the Secrets Manager mirror.

| Situation | What to do |
|---|---|
| **Routine rotation / compromised secret** | `tofu apply -replace='module.eks_addons.ravion_operator_credential.this[0]'`. The create mints a new secret and the control plane deletes the previous one — there is no `409` and no destroy-first step. The agent reconnects with the new pair when its Secret is updated. |
| **Credential lost with Terraform state** | The same replace. The secret cannot be re-read, ever — not by this module and not by Ravion — so recovery is always minting a new one. Nothing is stuck: the create does not conflict with the existing agent row, and `ravion_operator_agent_id` survives, so the cluster's history stays readable. |
| **Stop the agent now, without touching Terraform** | Ravion's kill switch, in the control plane: revoking the agent disables it and closes the live connection, and no token can be minted afterwards by anyone holding any secret. A disabled agent that reconnects is still admitted and then immediately handed its disable directive, so re-enabling never requires a customer to run `helm upgrade` during an incident. |
| **Offboard permanently** | `ravion_operator_enabled = false` and apply. Destroying `ravion_operator_credential` revokes the credential server-side, and the same apply removes both Helm releases (the agent and its Secret) and deletes the Secrets Manager mirror with no recovery window — the name is deterministic, so a 30-day window would block re-enabling Ravion Operator on this cluster for a month. |

Unlike the previous curl-based enrollment, turning the flag off **does** revoke the credential, because the destroy runs through the provider. The Ravion Operator row itself is retained (disabled) so the cluster's history is not orphaned.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| helm               | >= 3.0    |
| ravion (`providers.ravion.com/ravion/ravion`) | = 0.0.3-rc.1 — used only by `ravion_operator_enabled`; configured entirely from `RAVION_BASE_URL` / `RAVION_API_KEY` |

The Ravion provider is downloaded from the production registry, including when
`RAVION_BASE_URL` points to a development API. No local provider registry is needed.
The committed lock file verifies the immutable release packages.

For an existing workspace whose state references the former development provider
address, migrate that address before applying this module version:

```sh
tofu state replace-provider \
  'ravion-providers.ngrok.app/ravion/ravion' \
  'providers.ravion.com/ravion/ravion'
```

Run this against the existing configured remote workspace. It changes the provider
address in state without recreating infrastructure. New workspaces and runs that
failed during initialization have no provider resources to migrate.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the existing EKS cluster. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| tags | Tags applied to created resources and Karpenter-launched instances. | `map(string)` | `{}` | no |
| topology_aware_routing_enabled | Patch `kube-dns` with `trafficDistribution: PreferClose` so DNS stays zone-local (CoreDNS pods are spread by `compute/eks`). | `bool` | `true` | no |
| kubectl_image | kubectl image (`repository:tag`) for the `kube-dns` patch Jobs. | `string` | `registry.k8s.io/kubectl:v1.33.12` | no |
| karpenter_enabled | Install Karpenter end to end. | `bool` | `true` | no |
| ravion_runner_role_arn | IAM role assumed by `aws eks get-token` for Kubernetes API authentication. | `string` | `null` | no |
| aws_load_balancer_controller_enabled | Install the AWS Load Balancer Controller without any shared load balancer (it installs automatically with one). | `bool` | `false` | no |
| aws_load_balancer_controller_chart_version | aws-load-balancer-controller chart version. | `string` | `"1.14.0"` | no |
| aws_load_balancer_controller_namespace / aws_load_balancer_controller_service_account | Must match the Pod Identity association from `compute/eks`. | `string` | `"kube-system"` / `"aws-load-balancer-controller"` | no |
| aws_load_balancer_controller_helm_values | Extra YAML docs merged into the chart values. | `list(string)` | `[]` | no |
| karpenter_controller_namespace | Namespace for the controller and its Pod Identity association. | `string` | `"kube-system"` | no |
| karpenter_controller_service_account | Service account for the controller and its Pod Identity association. | `string` | `"karpenter"` | no |
| karpenter_chart_version | Karpenter (and karpenter-crd) chart version. | `string` | `"1.14.0"` | no |
| karpenter_node_role_additional_managed_policy_arns | Extra managed policies on the Karpenter node role. | `list(string)` | `[]` | no |
| karpenter_interruption_queue_name | Override interruption queue name (`karpenter-<cluster>` when null). | `string` | `null` | no |
| karpenter_interruption_queue_message_retention_seconds | Interruption queue retention. | `number` | `300` | no |
| karpenter_helm_values | Extra YAML docs merged into the Karpenter chart values. | `list(string)` | `[]` | no |
| karpenter_default_node_pool_creation_enabled | Create the default NodePool + EC2NodeClass. | `bool` | `true` | no |
| node_subnet_ids | Private subnets for the default NodePool and internal load balancers. Required when Karpenter's default NodePool, the private ALB, or the private NLB is enabled. | `list(string)` | `null` | no |
| cluster_security_group_id | Cluster security group for Karpenter nodes and load-balancer-to-pod ingress. Required when Karpenter's default NodePool or any shared load balancer is enabled. | `string` | `null` | no |
| karpenter_default_node_pool | Default NodePool settings (capacity types, categories, arch, CPU limit, expiry). | `object` | `{}` | no |
| eso_enabled | Install the External Secrets Operator, its Pod Identity role, and the Ravion ClusterSecretStores. | `bool` | `true` | no |
| eso_chart_version | external-secrets chart version. | `string` | `"2.8.0"` | no |
| eso_namespace | Namespace the operator is installed into (created if missing). | `string` | `"external-secrets"` | no |
| eso_service_account | Controller service account; must match the Pod Identity association. | `string` | `"external-secrets"` | no |
| eso_secret_and_parameter_arns | Secrets Manager / SSM ARNs (wildcards allowed) the operator may read. Empty means account- and region-wide read. | `list(string)` | `[]` | no |
| eso_kms_key_arns | Customer-managed KMS keys the operator may decrypt with. | `list(string)` | `[]` | no |
| eso_cluster_secret_stores_creation_enabled | Create the Ravion ClusterSecretStores. | `bool` | `true` | no |
| eso_secrets_manager_store_name | Name of the cluster-scoped Secrets Manager store (the app-chart default). | `string` | `"ravion-aws"` | no |
| eso_parameter_store_store_name | Name of the cluster-scoped Parameter Store store. | `string` | `"ravion-aws-parameter-store"` | no |
| eso_helm_values | Extra YAML docs merged into the external-secrets chart values. | `list(string)` | `[]` | no |
| ebs_csi_driver_enabled | Install the aws-ebs-csi-driver add-on + Pod Identity role. | `bool` | `false` | no |
| ebs_csi_addon_version / ebs_csi_addon_configuration_values | EBS CSI pin / JSON overrides. | `string` | `null` | no |
| logs_providers | Where container logs go: any of `loki`, `cloudwatch`, `grafana_cloud`, `datadog`, `new_relic`, `otlp`. `[]` turns logs off. Null falls back to the deprecated `logs_enabled`. | `list(string)` | `["loki"]` | no |
| metrics_providers | Where metrics go: any of `amp`, `cloudwatch`, `grafana_cloud`, `datadog`, `new_relic`, `otlp`. `[]` turns metrics off. Null falls back to the deprecated `metrics_enabled`. | `list(string)` | `["amp"]` | no |
| observability_namespace | Namespace for the collectors, the log store, and the materialized vendor credentials. Null shares Ravion Operator's namespace, which is what keeps Loki's Service URL stable. | `string` | `null` | no |
| logs_excluded_namespaces | Namespaces no log collector reads from, for every destination. | `list(string)` | `["kube-system", "kube-node-lease", "amazon-cloudwatch", "ravion-operator", "ravion-beacon"]` | no |
| logs_loki | `{ retention_days, s3_bucket_name, persistence_enabled, persistence_size }`. Falls back to the flat `log_retention_days` / `loki_s3_bucket_name` / `loki_persistence_*`. | `object` | `{}` | no |
| logs_cloudwatch | `{ retention_days, log_group_name }`. Default group `/ravion/eks/<cluster>`, retention 30 days. | `object` | `{}` | no |
| logs_grafana_cloud / metrics_grafana_cloud | `{ url, user, token_secret_arn, stack_url }` — the Loki push URL / Prometheus remote-write URL, the tenant id, the Secrets Manager ARN of the token, and the stack URL used for the deep link. | `object` | `{}` | no |
| logs_datadog / metrics_datadog | `{ site, api_key_secret_arn }`. Shared between the signals: whichever is set wins for both. | `object` | `{}` | no |
| logs_new_relic / metrics_new_relic | `{ region, license_key_secret_arn }`, region `us` or `eu`. | `object` | `{}` | no |
| logs_opensearch | `{ endpoint, index_prefix }`. The domain endpoint and index; requests are signed with `logs_opensearch_role_arn`. | `object` | `{}` | no |
| logs_splunk | `{ hec_url, hec_token_secret_arn, index }`. | `object` | `{}` | no |
| metrics_prometheus | `{ retention_days, storage_size, endpoint }`. `endpoint` points at a Prometheus you already run and skips the install. | `object` | `{}` | no |
| prometheus_chart_version / prometheus_helm_values | prometheus-community/prometheus chart version and value overrides. | `string` / `list(string)` | `"27.44.0"` / `[]` | no |
| logs_otlp / metrics_otlp | `{ endpoint, headers_secret_arn }`. The secret holds the value of an `Authorization` header. | `object` | `{}` | no |
| metrics_amp | `{ workspace_id, region, alias }`. Falls back to the flat `amp_workspace_id` / `amp_region` / `amp_alias`. | `object` | `{}` | no |
| metrics_cloudwatch | `{ enhanced_observability_enabled, application_signals_enabled, application_signals_namespaces, addon_version, addon_configuration_values }`. Auto-Monitor stays off unless Application Signals is enabled with no namespace list. | `object` | `{}` | no |
| otel_logs_collector_service_account / _resources / _helm_values | The log collector's identity, sizing, and value overrides. | mixed | `"ravion-otel-logs-collector"` / requests `100m`/`128Mi`, limit `512Mi` / `[]` | no |
| otel_contrib_image_repository / otel_contrib_image_tag / otel_contrib_command_name | The upstream contrib collector image, used by the log collector and by the metrics collector when a vendor exporter the AWS Distro lacks is selected. | `string` | `"docker.io/otel/opentelemetry-collector-contrib"` / `"0.137.0"` / `"otelcol-contrib"` | no |
| cloudwatch_observability_addon_version / cloudwatch_observability_addon_configuration_values | CloudWatch Observability pin / JSON overrides. Fallbacks for the `metrics_cloudwatch` fields of the same name. | `string` | `null` | no |
| amp_workspace_id | Existing AMP workspace to write into. Null creates one aliased `ravion-<cluster>`. | `string` | `null` | no |
| amp_region | Region the AMP workspace lives in. Null uses the cluster's region. | `string` | `null` | no |
| amp_alias | Alias for the created workspace. Null uses `ravion-<cluster_name>`. | `string` | `null` | no |
| metrics_namespace | Namespace for the metrics components. Null shares Ravion Operator's namespace. | `string` | `null` | no |
| scrape_interval_seconds | Scrape interval for every job (15-300). The first cost lever. | `number` | `60` | no |
| metrics_additional_allowlist | Extra whole-name metric regexes appended to the curated allow-list on every job. | `list(string)` | `[]` | no |
| otel_collector_chart_version | Community opentelemetry-collector chart version. | `string` | `"0.169.0"` | no |
| otel_collector_image_repository / otel_collector_image_tag / otel_collector_command_name | Metrics collector image and entrypoint. Null lets the module choose: the AWS Distro (which ships `sigv4auth`) for an AMP-only selection, contrib when a vendor exporter it lacks is selected. | `string` | `null` | no |
| otel_collector_service_account | Collector service account; the Pod Identity association binds to this name. | `string` | `"ravion-otel-collector"` | no |
| otel_collector_resources | Collector requests and limits. A memory limit is set by default because `memory_limiter` sizes itself against it. | `object` | requests `100m`/`256Mi`, limit `512Mi` | no |
| otel_collector_helm_values | Extra YAML docs merged into the collector chart values. | `list(string)` | `[]` | no |
| kube_state_metrics_enabled | Install kube-state-metrics alongside the collector (the source of every `kube_*` series). | `bool` | `true` | no |
| kube_state_metrics_chart_version | prometheus-community/kube-state-metrics chart version. | `string` | `"8.3.0"` | no |
| kube_state_metrics_helm_values | Extra YAML docs merged into the kube-state-metrics chart values. | `list(string)` | `[]` | no |
| grafana_role_creation_enabled | Create the IAM role Amazon Managed Grafana assumes to read the workspace and log groups. | `bool` | `false` | no |
| grafana_source_account_id | Account whose Grafana workspaces may assume that role (`aws:SourceAccount`). Null uses this account. | `string` | `null` | no |
| logs_enabled | Collect container logs with Alloy into an in-cluster Loki storing to S3 in this account. | `bool` | `false` | no |
| loki_s3_bucket_name | Existing bucket for log chunks and index. Null creates `ravion-loki-<cluster>-<account>`. | `string` | `null` | no |
| log_retention_days | How long logs stay queryable. Enforced by Loki's compactor; the bucket expires a week later as a backstop. | `number` | `30` | no |
| logs_namespace | Namespace for Loki and Alloy. Null shares Ravion Operator's namespace. | `string` | `null` | no |
| loki_chart_version | grafana/loki chart version. | `string` | `"7.3.0"` | no |
| loki_service_account | Loki's service account; the Pod Identity association binds to this name. | `string` | `"ravion-loki"` | no |
| loki_resources | Loki requests and limits. | `object` | requests `200m`/`512Mi`, limit `1Gi` | no |
| loki_persistence_enabled | Give Loki a PVC. Off by default — it needs a working StorageClass (`ebs_csi_driver_enabled`); an `emptyDir` is mounted at `/var/loki` instead. | `bool` | `false` | no |
| loki_persistence_size | Size of Loki's local working volume — PVC size when persistence is on, `emptyDir` size limit when off. | `string` | `"10Gi"` | no |
| loki_helm_values | Extra YAML docs merged into the Loki chart values. | `list(string)` | `[]` | no |
| alloy_chart_version | grafana/alloy chart version. | `string` | `"1.11.1"` | no |
| alloy_resources | Per-node Alloy requests and limits (multiplied by node count). | `object` | requests `100m`/`128Mi`, limit `512Mi` | no |
| alloy_helm_values | Extra YAML docs merged into the Alloy chart values. | `list(string)` | `[]` | no |
| grafana_enabled | Install Grafana in the cluster, preprovisioned with the AMP and Loki datasources. | `bool` | `false` | no |
| grafana_chart_version | grafana chart version, from the grafana-community repository. | `string` | `"12.10.4"` | no |
| grafana_namespace | Namespace for the in-cluster Grafana. Null shares Ravion Operator's namespace. | `string` | `null` | no |
| grafana_service_account | Grafana's service account; the AMP Pod Identity association binds to this name. | `string` | `"ravion-grafana"` | no |
| grafana_helm_values | Extra YAML docs merged into the Grafana chart values (ingress, persistence, dashboards). | `list(string)` | `[]` | no |
| ravion_operator_enabled | Mint the cluster's Ravion Operator credential (via the `ravion` provider) and install the Ravion Operator. | `bool` | `false` | no |
| ravion_operator_endpoint | WebSocket endpoint the agent dials. | `string` | `"wss://websockets.ravion.com/operator/v1/connect"` | no |
| ravion_operator_chart_source | Public OCI reference, or a filesystem chart path for local testing. | `string` | `"oci://public.ecr.aws/a8z1i1r2/operator"` | no |
| ravion_operator_chart_version | Ravion Operator **chart** version (not the agent version), pinned per module release. Null resolves the latest; ignored for a filesystem chart. | `string` | `"0.4.1"` | no |
| ravion_operator_namespace | Namespace for the agent and its credential Secret (created if missing). Shared observability components use it by default. | `string` | `"ravion-operator"` | no |
| ravion_operator_namespaces_creation_enabled | Create missing observation and deployment namespaces before installing Operator RBAC; reuse existing namespaces and retain created namespaces on removal. | `bool` | `true` | no |
| ravion_operator_namespace_scope | Namespaces the agent may observe. Empty is cluster-wide; non-empty renders namespaced Roles and no observation ClusterRole at all. | `list(string)` | `[]` | no |
| ravion_operator_deploy_enabled | Enable in-cluster deployments. | `bool` | `false` | no |
| ravion_operator_deploy_namespaces | Allowed namespaces; falls back to observation scope. Both lists must be empty for full management. | `list(string)` | `[]` | no |
| ravion_operator_execution_jobs_enabled | Durable isolated executor Jobs; disables self-update. | `bool` | `false` | no |
| ravion_operator_execution_image | Optional digest-pinned coordinator/executor image override; empty uses the published chart's bundled digest. | `string` | `""` | no |
| ravion_operator_execution_max_concurrent | Retained installation-wide capacity, 1-64; null selects 1 for full management or 4 for scoped Jobs. | `number` | `null` | no |
| ravion_operator_coordinator_enabled | Elected HA coordinators; requires Job mode. | `bool` | `false` | no |
| ravion_operator_coordinator_adaptive_enabled | Adapt coordinator count to eligible nodes, up to the replica limit. | `bool` | `true` | no |
| ravion_operator_coordinator_replicas | Maximum adaptive replicas or fixed count, 1-9. | `number` | `3` | no |
| ravion_operator_coordinator_distinct_nodes_enabled | Require a distinct node per coordinator. | `bool` | `true` | no |
| ravion_operator_full_management_enabled | Explicit wildcard Kubernetes RBAC and a single retained mutation lane. | `bool` | `false` | no |
| ravion_operator_exec_enabled | Grant `create` on `pods/exec` — the only way Ravion Operator can run a command inside a container. | `bool` | `false` | no |
| ravion_operator_self_update_enabled | Let the control plane roll the agent forward by patching its own Deployment. | `bool` | `true` | no |
| ravion_operator_image_tag | Agent image tag **pin**: asserted on every apply while set, released back to the control plane when removed (see above). Null: a fresh install starts at the chart's `appVersion` and upgrades keep the running image. | `string` | `null` | no |
| ravion_operator_helm_values | Extra YAML docs merged into the Ravion Operator chart values (`portForward`, `helmInventory`, `redaction`, `image.repository`, …). | `list(string)` | `[]` | no |
| ravion_operator_project_id / ravion_operator_environment_id / ravion_operator_aws_account_record_id | Ravion record ids recorded on the agent when its credential is minted. Optional. | `string` | `null` | no |
| public_subnet_ids | Public subnets for internet-facing load balancers. Required when the public ALB or public NLB is enabled. | `list(string)` | `[]` | no |
| load_balancer_deletion_protection_enabled | Deletion protection on the shared load balancers. | `bool` | `false` | no |
| public_alb_creation_enabled / private_alb_creation_enabled | Create a shared public / private ALB. | `bool` | `false` | no |
| public_alb_https_enabled / private_alb_https_enabled | HTTPS listener (with HTTP→HTTPS redirect). | `bool` | `false` | no |
| public_alb_certificate_arns / private_alb_certificate_arns | ACM certificates for the HTTPS listener (first is default, rest SNI). | `list(string)` | `[]` | no |
| public_alb_ssl_policy / private_alb_ssl_policy | HTTPS listener SSL policy. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| public_alb_idle_timeout / private_alb_idle_timeout | ALB idle timeout in seconds. | `number` | `60` | no |
| public_alb_ingress_cidr_blocks | IPv4 CIDRs allowed to reach the public ALB. | `list(string)` | `["0.0.0.0/0"]` | no |
| private_alb_ingress_cidr_blocks | IPv4 CIDRs allowed to reach the private ALB. | `list(string)` | RFC1918 ranges | no |
| public_alb_ingress_ipv6_cidr_blocks / private_alb_ingress_ipv6_cidr_blocks | IPv6 ingress CIDRs. | `list(string)` | `["::/0"]` / `[]` | no |
| public_alb_ingress_security_group_ids / private_alb_ingress_security_group_ids | Source security groups allowed to reach the ALB. | `list(string)` | `[]` | no |
| public_alb_web_acl_arn | WAFv2 Web ACL for the public ALB. | `string` | `null` | no |
| *_alb_access_logs_enabled / *_alb_access_logs_bucket_arn | ALB access logging toggle and existing bucket. | `bool` / `string` | `false` / `null` | no |
| public_nlb_creation_enabled / private_nlb_creation_enabled | Create a shared public / private NLB. | `bool` | `false` | no |
| *_nlb_cross_zone_load_balancing_enabled | NLB cross-zone load balancing. | `bool` | `false` | no |
| *_nlb_security_group_ids | Additional security groups on the NLB. | `list(string)` | `[]` | no |
| *_nlb_elastic_ips_enabled / *_nlb_elastic_ip_allocation_ids | Static Elastic IPs for the NLB, one allocation per subnet. | `bool` / `list(string)` | `false` / `[]` | no |
| *_nlb_access_logs_enabled / *_nlb_access_logs_bucket_arn | NLB access logging toggle and existing bucket. | `bool` / `string` | `false` / `null` | no |

## Outputs

All outputs are null when the corresponding add-on is disabled.

| Name | Description |
|------|-------------|
| karpenter_namespace / karpenter_chart_version | Karpenter controller install location and version. |
| karpenter_default_node_pool_release | Helm release name of the default NodePool chart. |
| karpenter_controller_role_arn / karpenter_node_role_arn | Karpenter IAM roles. |
| karpenter_node_instance_profile_name | Instance profile used by the default EC2NodeClass. |
| karpenter_interruption_queue_name | SQS interruption queue name. |
| lb_controller_chart_version / lb_controller_namespace | Load balancer controller install version and location. |
| eso_namespace / eso_chart_version | External Secrets Operator install location and version. |
| eso_role_arn | External Secrets Operator Pod Identity role. |
| eso_secrets_manager_store_name / eso_parameter_store_store_name | `ClusterSecretStore` names workload charts reference. |
| ebs_csi_addon_version / ebs_csi_role_arn | EBS CSI add-on version and Pod Identity role. |
| cloudwatch_observability_addon_version / cloudwatch_observability_role_arn | CloudWatch Observability add-on version and Pod Identity role. |
| cloudwatch_application_signals_namespaces | Namespaces Application Signals was asked for. Auto-Monitor stays cluster-wide-off when this is non-empty; annotate exactly these. |
| logs_providers / metrics_providers | The destinations selected, as given. |
| logs_rendering_providers / metrics_rendering_providers | The selected destinations Ravion can read, **in fallback order** (`loki → cloudwatch`, `amp → prometheus → cloudwatch`). Empty when the signal is off or only ship-only destinations are selected. |
| logs_cloudwatch_log_group | `/ravion/eks/<cluster>`, one stream per pod as `<namespace>/<pod>/<container>` (null unless `cloudwatch` is a logs destination). |
| logs_external_links / metrics_external_links | One `{ provider, name, href_prefix }` per ship-only destination; the caller appends its own query to `href_prefix`. |
| prometheus_endpoint | In-cluster Prometheus base URL (null unless `prometheus` is a metrics destination). |
| grafana_cloud_logs_query_url / grafana_cloud_metrics_query_url | Grafana Cloud query base URLs, derived from the push URLs and named in Ravion Operator's proxy allowlist. |
| observability_credentials_secret_name / observability_proxy_credentials | The Secret in Ravion Operator's namespace the agent presents when proxying a query to an external store, and the full `{ endpointPrefix, secretName, kind }` mapping. |
| observability_namespace | Namespace the collectors, the log store, and the vendor credentials live in. |
| otel_logs_collector_role_arn / logs_opensearch_role_arn | The log collector's Pod Identity role: scoped to the Ravion log group, and the role to map into an OpenSearch domain. |
| prometheus_chart_version | Installed prometheus chart version (null unless the module installed one). |
| amp_workspace_id / amp_workspace_arn / amp_region | The AMP workspace this cluster's metrics land in — created, or the one passed in. |
| amp_remote_write_endpoint / amp_query_endpoint | Where the collector writes, and the Prometheus-compatible base URL to query (a Grafana datasource URL as-is). |
| amp_remote_write_role_arn | Collector Pod Identity role, scoped to `aps:RemoteWrite` on that one workspace. |
| metrics_namespace | Namespace the metrics components are installed into. |
| otel_collector_chart_version / kube_state_metrics_chart_version | Installed chart versions for the metrics pipeline. |
| grafana_role_arn | Role Amazon Managed Grafana assumes to query the AMP workspace. |
| loki_endpoint | In-cluster base URL of Loki. Reachable only from inside the cluster — it is what Ravion Operator's proxy allowlist names. |
| loki_namespace | Namespace Loki and Alloy are installed into. |
| loki_s3_bucket / loki_s3_bucket_arn | Bucket holding the log chunks and index. |
| loki_role_arn | Loki's Pod Identity role, scoped to read, write, and delete on that bucket alone. |
| log_retention_days | How long logs stay queryable. |
| loki_chart_version / alloy_chart_version | Installed chart versions for the logs pipeline. |
| grafana_namespace / grafana_service | Where the in-cluster Grafana is, for a port-forward. |
| grafana_amp_role_arn | In-cluster Grafana's Pod Identity role for querying AMP. Distinct from `grafana_role_arn`, which is for AMG reaching in from outside. |
| ravion_operator_namespace / ravion_operator_chart_version | Ravion Operator install location and **chart** version (not the running agent version — the control plane owns that). |
| ravion_operator_agent_id | Ravion Operator record id (`opagt_…`). Stable across rotations — correlate agent logs by it. |
| ravion_operator_installation_id | Stable provider-neutral installation ID; same value as ravion_operator_agent_id. |
| ravion_operator_execution_image | Configured image override; empty when using the chart's bundled digest, or null when Operator or Job mode is disabled. |
| ravion_operator_client_id | WorkOS M2M client id the agent authenticates as. Not a secret, and shared by every cluster in the organization. |
| ravion_operator_client_secret_id | WorkOS id of the secret issued to this cluster (not the secret). Identifies which credential a connecting agent presents. |
| ravion_operator_credential_secret_arn | Secrets Manager secret mirroring the credential — an operator recovery copy of what Terraform state holds. |
| public_alb_arn / dns_name / zone_id / arn_suffix / security_group_id / http_listener_arn / https_listener_arn | Shared public ALB attributes for workload target groups, DNS records, and metrics. |
| private_alb_arn / dns_name / zone_id / arn_suffix / security_group_id / http_listener_arn / https_listener_arn | Shared private ALB attributes. |
| public_nlb_arn / dns_name / zone_id / arn_suffix / security_group_id | Shared public NLB attributes. |
| private_nlb_arn / dns_name / zone_id / arn_suffix / security_group_id | Shared private NLB attributes. |

## Notes

- `kube-dns` zone-local routing is a local chart (`charts/coredns-traffic-distribution`) whose Helm hook Jobs run `kubectl patch` against the Service, for the same reason as the other local charts: the Helm provider is the only Kubernetes access this stack has, and Helm cannot adopt a Service the coredns add-on owns. The `post-install`/`post-upgrade` hook writes `spec.trafficDistribution`, the `pre-delete` hook clears it, so `topology_aware_routing_enabled = false` is a real rollback. The Job's Role can `get` and `patch` exactly one Service.
- Karpenter CRDs are managed by the dedicated `karpenter-crd` chart because Helm does not upgrade CRDs bundled inside a chart's `crds/` directory. Both charts are pinned to the same version.
- The default NodePool and EC2NodeClass are delivered as a local chart (`charts/karpenter-resources`) because the Helm provider is the only Kubernetes access this stack has.
- On destroy, the Helm releases are removed before the AWS-side resources, so Karpenter drains and terminates the nodes it launched while its IAM roles and queue still exist.
- The cluster must have the Pod Identity Agent add-on (the `compute/eks` composite installs it by default); Karpenter's node access entry additionally requires `authentication_mode = API`.
- The load balancer controller's IAM role and Pod Identity association come from the `compute/eks` composite (`aws_load_balancer_controller_pod_identity_creation_enabled`, on by default); this stack only installs the chart, with `region` and `vpcId` set explicitly so it works under restricted IMDS and on Fargate.
- For automatic subnet discovery, tag public subnets with `kubernetes.io/role/elb = 1` and private subnets with `kubernetes.io/role/internal-elb = 1`, or specify subnets per Ingress via the `alb.ingress.kubernetes.io/subnets` annotation.
- Unlike Karpenter, the `external-secrets` chart renders its CRDs as ordinary templates (`installCRDs`, default on), so Helm upgrades them and no separate CRD chart is needed. The `ClusterSecretStore`s are a separate local chart (`charts/external-secrets-resources`) that `depends_on` the operator release, because CRD-kind objects cannot be applied before the operator's CRDs exist and its validating webhook is serving.
- The External Secrets Operator's `ClusterSecretStore`s carry no `auth` block. The operator resolves credentials through the AWS SDK default credential chain, which the Pod Identity Agent populates from the association this stack creates — so no static AWS credentials exist anywhere in the cluster, and `serviceAccountRef`-style IRSA config is deliberately absent (it conflicts with Pod Identity).
- The `grafana` Helm chart moved: Grafana Labs deprecated their copy on `grafana.github.io/helm-charts` in January 2026 and handed it to `grafana-community`, which is where this module pulls it from. The `loki` and `alloy` charts did not move and still come from `grafana.github.io/helm-charts`.
- Loki's compactor is what enforces retention, and it is **off** in stock Loki. That is why the module sets `retention_enabled` explicitly and why Loki's IAM role carries `s3:DeleteObject` — a role scoped to read and write only would let the bucket grow forever while looking correctly least-privilege.
- Every Helm chart and container image this module installs is **pinned by a variable with a default**, and the defaults move only in a module release. That includes both pipelines: `otel_collector_chart_version`, `otel_collector_image_tag`, `kube_state_metrics_chart_version`, `loki_chart_version`, `alloy_chart_version`, and `grafana_chart_version`. Overriding one is supported; letting a chart float is not an option the module offers, because a silent upstream bump is an unreviewable change to what runs in a customer's cluster.
- The metrics collector scrapes the kubelet through the **API server proxy**, not each node's port 10250. That is why it needs `nodes/proxy` in its ClusterRole and why it works unchanged on private-endpoint clusters — the only network path it requires is to the Kubernetes API.
- The AMP workspace uses the AWS provider's per-resource `region` argument rather than a second provider configuration, so `amp_region` moves the workspace without any aliased-provider plumbing in consumers.
- Loki is reachable only from inside the cluster, and that is load-bearing rather than incidental: it is what removes the need for an ingress, a certificate, an authentication layer in front of it, and any inbound path into the customer's VPC. The one route in is Ravion Operator's proxy, whose allowlist this module writes.
- Ravion Operator's credential `Secret` is a separate local chart (`charts/beacon-credential`) rather than a `kubernetes_secret` resource, for the same reason as the `ClusterSecretStore`s: the Helm provider is the only Kubernetes access this stack has. The credential reaches it through `values` wrapped in `sensitive()`, not through `set_sensitive` — Helm's `--set` parser splits on `,`, `.` and `=`, which silently truncates a client secret containing any of them.
- The Ravion Operator chart deliberately creates no credential `Secret` of its own, and grants Ravion Operator **no RBAC on Secrets at all**. The kubelet reads that object and projects it into the container as a read-only volume, which is what keeps the base ClusterRole free of Secret access.
- The Ravion Operator credential is a Terraform resource (`ravion_operator_credential`), not a provisioner. A `local-exec` curl used to enroll the cluster and treat the Secrets Manager copy as the idempotency anchor, because the plaintext is returned once and a re-run on a fresh runner had to answer "already enrolled?" with no local state. The provider dissolves that problem rather than working around it: create is idempotent-by-replacement — a create for an already-registered cluster ARN mints a new secret and revokes the old one — so **state is the anchor and Secrets Manager is only a mirror**. It also means no `curl` on the runner, no API-token module input, and nothing enrolled during a plan nobody applies.
- `ravion_operator_enabled = false` now **does** revoke the credential, because the destroy runs through the provider. The agent row is retained, disabled, so the cluster's history is not orphaned.
- Both collectors fan out rather than duplicating themselves: several destinations are several exporters (or several `loki.write` blocks) on one pipeline, so the node's log files are read once and the cluster scraped once regardless of how many vendors receive a copy. Vendor agents are deliberately not installed — each would be another DaemonSet with its own RBAC, upgrade cadence, and opinions about labels, and every vendor here accepts what Alloy or the OpenTelemetry Collector already produces.
- The `awscloudwatchlogs` exporter is configured with both a static `log_group_name` and per-record `aws.log.group.names` / `aws.log.stream.names` resource attributes. The attributes are what give one stream per pod; the static value is the floor, so a collector version that ignores them still writes to the right group. Worth re-checking on a collector upgrade.
- `agent.enabled` in the CloudWatch add-on's configuration is the one key here not lifted verbatim from AWS's documented examples; it is how the chart switches the metrics DaemonSet off for a logs-only selection. If the EKS API ever rejects it during schema validation, drop it (the metrics agent then runs beside a logs-only selection) or override the document through `metrics_cloudwatch.addon_configuration_values`.
- There is no ordering concern for the Deployment-kind add-ons here (External Secrets Operator, Karpenter, load balancer controller): this stack deploys against a cluster whose system node group already exists, which is what the `compute/eks` composite's cluster → system node group → Deployment-kind add-on chain guarantees.
