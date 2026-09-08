# EKS Add-ons

Selectable autoscaling, load balancing, storage, external secrets, namespace
bootstrap, logs and metrics for an existing EKS cluster. Cluster management uses
the [`compute/eks`](..) module's dedicated private SSM relay and separate read
and deploy/admin roles. New configurations install no Ravion Operator and mint
no Operator credentials.

Read-access RBAC bootstrap is always installed, including when all optional
add-ons and telemetry destinations are disabled; add-ons therefore requires
Kubernetes API connectivity in every configuration.

**Existing installations:** follow [UPGRADE-SSM.md](UPGRADE-SSM.md) before changing
the module ref. Revoke the old WorkOS credential and remove its deployment and
credential copies before detaching custom-provider state. Non-destructive
`removed` blocks are an accidental-destruction guard, not an uninstall mechanism.

## Usage

```hcl
module "eks_addons" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks/addons?ref=main"

  cluster_name              = module.eks.cluster_name
  region                    = module.eks.region
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_subnet_ids            = module.eks.node_subnet_ids
  ravion_runner_role_arn     = module.eks.ravion_runner_role_arn

  workload_namespaces = ["app-production"]
  observed_namespaces = ["shared-services"]
  ebs_csi_driver_enabled = true
  logs_providers        = ["loki"]
  metrics_providers     = ["amp"]

  eso_secret_and_parameter_arns = ["arn:aws:secretsmanager:us-east-2:111122223333:secret:prod/*"]
  public_alb_creation_enabled   = true
  public_alb_https_enabled      = true
  public_alb_certificate_arns   = [aws_acm_certificate.main.arn]
  public_subnet_ids             = module.network.public_subnet_ids
}
```

Pin production to a published module-definition tag or verified commit SHA.
The authored add-ons version remains `0.8.4` for this coordinated local prerelease.

## Connectivity and access

OpenTofu's Helm provider still runs in a Terraform execution environment that
can reach the EKS API, typically inside the VPC with the cluster's
`ravion_runner_security_group_id` attached. The AWS CLI must be available for
`aws eks get-token`. Setting `ravion_runner_role_arn` assumes the permanent EKS
cluster-admin Runner role; otherwise the execution identity must have cluster
access. This module does not start a session-manager plugin for the Helm provider.
The tower runtime uses the dedicated SSM relay for management and workload operations.

The cluster read role has AmazonEKSViewPolicy and the `ravion:readers` group.
AWS View omits nodes and live metrics. A read-only inventory ClusterRole/Binding
adds nodes, persistent volumes, storage classes, metrics.k8s.io pods/nodes, and
Karpenter nodepools/nodeclaims/nodeclasses with get/list/watch only.
Add-ons installs a small read-only Role/RoleBinding allowing **GET services/proxy**
only for selected managed Loki and Prometheus services, in their respective
namespaces. The service-proxy and cluster-inventory charts grant no Secrets
access, exec, pod-forward, or write verbs. Separately, the retained namespace
bootstrap chart grants `ravion:readers` **get/list Secrets** in each configured
workload/observed namespace for Helm storage inventory and drift detection.
This includes every Secret's contents in those namespaces, including non-Helm
application/ESO Secrets: Kubernetes RBAC cannot selector-limit Secret listing.
There is no global Secret grant and no Secret write grant.

Read managed stores through the Kubernetes API over the EKS-only SSM tunnel:

```text
/api/v1/namespaces/<namespace>/services/http:ravion-loki:3100/proxy/loki/api/v1/query_range
/api/v1/namespaces/<namespace>/services/http:ravion-prometheus-server:9090/proxy/api/v1/query
```

Convert query POST form parameters to GET query parameters. External or custom
Prometheus endpoints need separately provisioned access in their namespace.
Authorized interactive users can use the cluster admin role for exec and
port-forward; observers must never receive that role automatically.

## Stable namespaces and storage

The default shared namespace remains **`ravion-operator`** despite the removal
of Operator. `observability_namespace` controls it independently;
`logs_namespace`, `metrics_namespace`, and `grafana_namespace` retain their
overrides. Existing installations that inherited a custom Operator namespace
must set it explicitly before upgrading. Namespace changes do not migrate PVCs.

Existing observability Helm release names and resource addresses, Loki S3 bucket,
AMP workspace, and persistent volume settings remain stable. Vendor ESO Secret
names are preserved. No namespace is deleted as part of Operator retirement.

The sorted, deduplicated union of `workload_namespaces` (deployment scope) and
`observed_namespaces` (additional observation scope) drives bootstrap and Helm
Secret read permissions. Empty lists grant no Secret access. This union is
published as `ravion_access_helm_inventory_namespaces`; configure the observer's
Helm inventory/preflight scope to match it. The shared `ravion-operator` namespace
is not implicitly added to this permission scope.

Namespace bootstrap uses the existing
`helm_release.ravion_operator_namespaces` address and `ravion-operator-namespaces`
chart/release in `kube-system`. These names are retained for state continuity.
Existing namespaces are reused without adoption. Created namespaces carry Helm's
keep policy and survive list removal, disabling bootstrap, and release uninstall.
Set `workload_namespaces_creation_enabled = false` for externally managed
namespaces: creation stops but the namespaced Helm inventory Roles/RoleBindings
are still installed. The namespaces must already exist in this mode. Removing
a namespace from both lists removes its generated read Role/RoleBinding while
retaining the Namespace; RBAC resources deliberately have no keep annotation.

## Add-ons

| Add-on | Configuration | Default |
|---|---|---|
| Karpenter | `karpenter_enabled`, default NodePool settings | Enabled |
| AWS Load Balancer Controller | Automatic with shared LBs, or explicit opt-in | Automatic |
| External Secrets Operator | `eso_enabled` | Enabled |
| EBS CSI | `ebs_csi_driver_enabled` | Disabled |
| Shared ALB/NLB | Public/private creation toggles | Disabled in Terraform; public ALB enabled in form |
| Namespace bootstrap and Helm inventory reads | `workload_namespaces`, `observed_namespaces`, creation toggle | Empty namespace lists; no Secret access |
| Loki + Alloy logs | `logs_providers` | `["loki"]` |
| AMP + OpenTelemetry metrics | `metrics_providers` | `["amp"]` |
| In-cluster Grafana | `grafana_enabled` | Disabled |
| Managed Grafana query role | `grafana_role_creation_enabled` | Disabled |

Karpenter provisions node/controller roles, Pod Identity, an interruption queue,
EventBridge rules and the controller/CRD charts. Its default NodePool requires
node subnet and cluster security group wiring. The load balancer controller is
installed before the Karpenter resources that depend on its webhook.

Shared load balancers are Terraform-managed. Workload modules attach target
groups through `TargetGroupBinding`; no per-workload ALB is required. Public
LBs use public subnets; private LBs use node subnets. Their security groups can
reach cluster pods. HTTPS needs ACM certificates; deletion protection is supported.

## External secrets

ESO reads referenced AWS secrets through Pod Identity. Values never pass through
Terraform variables or Helm history. Workload charts use these cluster stores:

| AWS backend | Store | Kind |
|---|---|---|
| Secrets Manager | `ravion-aws` | `ClusterSecretStore` |
| SSM Parameter Store | `ravion-aws-parameter-store` | `ClusterSecretStore` |

Scope `eso_secret_and_parameter_arns` to permitted resources. Empty means all
secrets/parameters in this account and region. Customer-managed encryption keys
also require `eso_kms_key_arns`. Kubernetes Secrets inherit EKS envelope encryption.

## Logs and metrics

Each signal accepts multiple destinations; `[]` disables it. Collectors fan out
from one collection pipeline. API keys/tokens are Secrets Manager references
materialized with ESO; selecting a credential-bearing vendor without ESO fails.

| Signal | Destinations |
|---|---|
| Logs | Loki, CloudWatch, Grafana Cloud, Datadog, New Relic, OpenSearch, Splunk, OTLP |
| Metrics | AMP, in-cluster Prometheus, CloudWatch, Grafana Cloud, Datadog, New Relic, OTLP |

Ravion's rendering fallback order is logs **Loki → CloudWatch** and metrics
**AMP → Prometheus → CloudWatch**. Vendors are ship-only destinations with links;
materialized query credential references are retained for compatible backends.
Workload log sources already use `{type: eks_loki, cluster_arn, selector}` and
need no Operator agent identifier.

Loki is single-binary, S3-backed, with retention enforced by the compactor and a
bucket lifecycle backstop. There is no ingress or gateway. Alloy attaches
namespace/workload/pod/container labels. CloudWatch's collector uses
`/ravion/eks/<cluster>` and streams `<namespace>/<pod>/<container>`; this is separate
from the Container Insights application log group. Both collectors respect
`logs_excluded_namespaces`, including the current and legacy shared namespaces.

AMP receives curated metrics via SigV4 remote write. In-cluster Prometheus is a
remote-write receiver, not a duplicate scraper; it requires a working storage
class for persistence. Bring an existing workspace or Prometheus endpoint through
the corresponding provider settings. Grafana can query configured stores privately.

CloudWatch Container Insights runs only when selected. Auto-Monitor is pinned off
unless Application Signals auto-instrumentation is explicitly enabled; merely
choosing CloudWatch does not inject agents or restart every workload.

## Verification

```sh
tofu init -backend=false
tofu validate
tofu test
python3 tests/test_namespace_chart.py
python3 tests/test_observability_access_chart.py
```

OpenTofu tests use mocked providers and make no AWS changes. Network reachability,
SSM registration/session cleanup, IAM effective permissions, and provider-driven
legacy credential revocation require verification during the staged cutover.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.55.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.2.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_amp_remote_write_role"></a> [amp\_remote\_write\_role](#module\_amp\_remote\_write\_role) | ../../../security/iam | n/a |
| <a name="module_cloudwatch_observability_role"></a> [cloudwatch\_observability\_role](#module\_cloudwatch\_observability\_role) | ../../../security/iam | n/a |
| <a name="module_ebs_csi_role"></a> [ebs\_csi\_role](#module\_ebs\_csi\_role) | ../../../security/iam | n/a |
| <a name="module_external_secrets_role"></a> [external\_secrets\_role](#module\_external\_secrets\_role) | ../../../security/iam | n/a |
| <a name="module_grafana_role"></a> [grafana\_role](#module\_grafana\_role) | ../../../security/iam | n/a |
| <a name="module_grafana_workspace_read_role"></a> [grafana\_workspace\_read\_role](#module\_grafana\_workspace\_read\_role) | ../../../security/iam | n/a |
| <a name="module_karpenter"></a> [karpenter](#module\_karpenter) | ./modules/eks_karpenter | n/a |
| <a name="module_loki_bucket"></a> [loki\_bucket](#module\_loki\_bucket) | ../../../storage/s3 | n/a |
| <a name="module_loki_role"></a> [loki\_role](#module\_loki\_role) | ../../../security/iam | n/a |
| <a name="module_otel_logs_collector_role"></a> [otel\_logs\_collector\_role](#module\_otel\_logs\_collector\_role) | ../../../security/iam | n/a |
| <a name="module_private_alb"></a> [private\_alb](#module\_private\_alb) | ../../../networking/alb | n/a |
| <a name="module_private_nlb"></a> [private\_nlb](#module\_private\_nlb) | ../../../networking/nlb | n/a |
| <a name="module_public_alb"></a> [public\_alb](#module\_public\_alb) | ../../../networking/alb | n/a |
| <a name="module_public_nlb"></a> [public\_nlb](#module\_public\_nlb) | ../../../networking/nlb | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_eks_addon.cloudwatch_observability](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_pod_identity_association.cloudwatch_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.fluent_bit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.grafana](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.loki](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.otel_collector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.otel_logs_collector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_prometheus_workspace.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_private_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_private_nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_public_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_public_nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [helm_release.alloy](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.external_secrets](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.external_secrets_stores](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.grafana](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.karpenter](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.karpenter_crd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.karpenter_default_node_pool](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.kube_state_metrics](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.lb_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.loki](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.observability_access](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.observability_secrets](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.otel_collector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.otel_logs_collector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.prometheus](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.ravion_operator_namespaces](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster) | data source |
| [aws_iam_policy_document.amp_remote_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.grafana_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.grafana_workspace_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.loki_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.otel_logs_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alloy_chart_version"></a> [alloy\_chart\_version](#input\_alloy\_chart\_version) | Version of the grafana/alloy Helm chart to install. | `string` | `"1.11.1"` | no |
| <a name="input_alloy_helm_values"></a> [alloy\_helm\_values](#input\_alloy\_helm\_values) | Extra YAML documents merged into the grafana/alloy chart values, after the values this module derives (later entries win). The route to tolerations, node selectors, or extra Alloy components. | `list(string)` | `[]` | no |
| <a name="input_alloy_resources"></a> [alloy\_resources](#input\_alloy\_resources) | Resource requests and limits for each Alloy pod. It runs on every node, so this is multiplied by the node count - the defaults are deliberately small. Null limits are omitted. | <pre>object({<br/>    cpu_request    = optional(string, "100m")<br/>    memory_request = optional(string, "128Mi")<br/>    cpu_limit      = optional(string)<br/>    memory_limit   = optional(string, "512Mi")<br/>  })</pre> | `{}` | no |
| <a name="input_amp_alias"></a> [amp\_alias](#input\_amp\_alias) | Alias for the created AMP workspace. When null, 'ravion-<cluster\_name>' is used. Ignored when amp\_workspace\_id is set. | `string` | `null` | no |
| <a name="input_amp_region"></a> [amp\_region](#input\_amp\_region) | Region the AMP workspace lives in. When null, the cluster's region is used. Set this for clusters in regions where AMP is unavailable: remote write works cross-region, at the cost of inter-region data transfer. | `string` | `null` | no |
| <a name="input_amp_workspace_id"></a> [amp\_workspace\_id](#input\_amp\_workspace\_id) | Existing Amazon Managed Prometheus workspace to write into (ws-...). When null, the module creates one for this cluster. Bring your own to share a workspace between clusters, or to write into a workspace in another region. | `string` | `null` | no |
| <a name="input_aws_load_balancer_controller_chart_version"></a> [aws\_load\_balancer\_controller\_chart\_version](#input\_aws\_load\_balancer\_controller\_chart\_version) | Version of the aws-load-balancer-controller Helm chart to install. | `string` | `"1.14.0"` | no |
| <a name="input_aws_load_balancer_controller_enabled"></a> [aws\_load\_balancer\_controller\_enabled](#input\_aws\_load\_balancer\_controller\_enabled) | Install the AWS Load Balancer Controller even when no shared load balancer is enabled, e.g. to provision ALBs/NLBs directly from Ingress and LoadBalancer resources. The controller is installed automatically whenever any shared load balancer is enabled, since workload target registration (TargetGroupBinding) depends on it. | `bool` | `false` | no |
| <a name="input_aws_load_balancer_controller_helm_values"></a> [aws\_load\_balancer\_controller\_helm\_values](#input\_aws\_load\_balancer\_controller\_helm\_values) | Extra YAML documents merged into the aws-load-balancer-controller chart values (later entries win). | `list(string)` | `[]` | no |
| <a name="input_aws_load_balancer_controller_namespace"></a> [aws\_load\_balancer\_controller\_namespace](#input\_aws\_load\_balancer\_controller\_namespace) | Namespace the controller is installed into. Must match the Pod Identity association created by the compute/eks stack. | `string` | `"kube-system"` | no |
| <a name="input_aws_load_balancer_controller_service_account"></a> [aws\_load\_balancer\_controller\_service\_account](#input\_aws\_load\_balancer\_controller\_service\_account) | Service account name for the controller. Must match the Pod Identity association created by the compute/eks stack. | `string` | `"aws-load-balancer-controller"` | no |
| <a name="input_cloudwatch_observability_addon_configuration_values"></a> [cloudwatch\_observability\_addon\_configuration\_values](#input\_cloudwatch\_observability\_addon\_configuration\_values) | JSON string of add-on configuration overrides for amazon-cloudwatch-observability. | `string` | `null` | no |
| <a name="input_cloudwatch_observability_addon_version"></a> [cloudwatch\_observability\_addon\_version](#input\_cloudwatch\_observability\_addon\_version) | Pinned version for the amazon-cloudwatch-observability add-on. When null, AWS resolves the most recent compatible version. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the existing EKS cluster to install add-ons onto. | `string` | n/a | yes |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | EKS-managed cluster security group (cluster\_security\_group\_id output of the compute/eks stack). Attached to Karpenter-launched nodes and opened to shared load balancers so they can reach pods. Required when Karpenter's default NodePool or any shared load balancer is enabled. | `string` | `null` | no |
| <a name="input_ebs_csi_addon_configuration_values"></a> [ebs\_csi\_addon\_configuration\_values](#input\_ebs\_csi\_addon\_configuration\_values) | JSON string of add-on configuration overrides for aws-ebs-csi-driver. | `string` | `null` | no |
| <a name="input_ebs_csi_addon_version"></a> [ebs\_csi\_addon\_version](#input\_ebs\_csi\_addon\_version) | Pinned version for the aws-ebs-csi-driver add-on. When null, AWS resolves the most recent compatible version. | `string` | `null` | no |
| <a name="input_ebs_csi_driver_enabled"></a> [ebs\_csi\_driver\_enabled](#input\_ebs\_csi\_driver\_enabled) | Install the aws-ebs-csi-driver add-on and create its Pod Identity role so workloads can use EBS-backed persistent volumes. | `bool` | `false` | no |
| <a name="input_eso_chart_version"></a> [eso\_chart\_version](#input\_eso\_chart\_version) | Version of the external-secrets Helm chart to install. | `string` | `"2.8.0"` | no |
| <a name="input_eso_cluster_secret_stores_creation_enabled"></a> [eso\_cluster\_secret\_stores\_creation\_enabled](#input\_eso\_cluster\_secret\_stores\_creation\_enabled) | Create the Ravion ClusterSecretStores. Disable to manage SecretStore resources yourself; workload charts then need their own store reference. | `bool` | `true` | no |
| <a name="input_eso_enabled"></a> [eso\_enabled](#input\_eso\_enabled) | Install the External Secrets Operator, its Pod Identity role, and the Ravion ClusterSecretStores. Workloads then reference Secrets Manager secrets and SSM parameters by ARN and ESO materializes them into Kubernetes Secrets, so secret values never pass through Ravion, Helm values, or release history. | `bool` | `true` | no |
| <a name="input_eso_helm_values"></a> [eso\_helm\_values](#input\_eso\_helm\_values) | Extra YAML documents merged into the external-secrets chart values, after the values this module derives (CRD install, service account). Later entries win. | `list(string)` | `[]` | no |
| <a name="input_eso_kms_key_arns"></a> [eso\_kms\_key\_arns](#input\_eso\_kms\_key\_arns) | Customer-managed KMS key ARNs the operator may decrypt with. Only needed for secrets or parameters encrypted with a customer-managed key; the AWS-managed aws/secretsmanager and aws/ssm keys need no explicit grant. | `list(string)` | `[]` | no |
| <a name="input_eso_namespace"></a> [eso\_namespace](#input\_eso\_namespace) | Kubernetes namespace the External Secrets Operator is installed into. Created if it does not exist. | `string` | `"external-secrets"` | no |
| <a name="input_eso_parameter_store_store_name"></a> [eso\_parameter\_store\_store\_name](#input\_eso\_parameter\_store\_store\_name) | Name of the cluster-scoped AWS SSM Parameter Store store. A separate store is required because ESO's AWS provider takes a single service per store. | `string` | `"ravion-aws-parameter-store"` | no |
| <a name="input_eso_secret_and_parameter_arns"></a> [eso\_secret\_and\_parameter\_arns](#input\_eso\_secret\_and\_parameter\_arns) | Secrets Manager secret and SSM parameter ARNs (wildcards allowed) the operator may read. When empty, the role can read every secret and parameter in this account and region. Set this to scope the role down, or to grant access to other regions and accounts. | `list(string)` | `[]` | no |
| <a name="input_eso_secrets_manager_store_name"></a> [eso\_secrets\_manager\_store\_name](#input\_eso\_secrets\_manager\_store\_name) | Name of the cluster-scoped AWS Secrets Manager store. This is the store name Ravion app charts default to. | `string` | `"ravion-aws"` | no |
| <a name="input_eso_service_account"></a> [eso\_service\_account](#input\_eso\_service\_account) | Service account name for the External Secrets Operator controller. Must match the chart's service account, since the Pod Identity association binds credentials to this name. | `string` | `"external-secrets"` | no |
| <a name="input_grafana_chart_version"></a> [grafana\_chart\_version](#input\_grafana\_chart\_version) | Version of the grafana Helm chart to install, from the grafana-community repository - the maintained home of this chart since Grafana Labs deprecated their copy in January 2026. | `string` | `"12.10.4"` | no |
| <a name="input_grafana_enabled"></a> [grafana\_enabled](#input\_grafana\_enabled) | Install Grafana in the cluster, preprovisioned with both Ravion datasources: Amazon Managed Prometheus over SigV4 and the in-cluster Loki. This is the only way to see the logs in Grafana - Amazon Managed Grafana runs outside the cluster and cannot reach Loki, which is deliberately not exposed. No ingress is created; reach it with a port-forward or add one through grafana\_helm\_values. | `bool` | `false` | no |
| <a name="input_grafana_helm_values"></a> [grafana\_helm\_values](#input\_grafana\_helm\_values) | Extra YAML documents merged into the grafana/grafana chart values, after the values this module derives (later entries win). The route to an ingress, persistence, an admin password from an existing secret, dashboards, or resources. | `list(string)` | `[]` | no |
| <a name="input_grafana_namespace"></a> [grafana\_namespace](#input\_grafana\_namespace) | Kubernetes namespace for Grafana. Null uses observability\_namespace (default ravion-operator). Created if missing. | `string` | `null` | no |
| <a name="input_grafana_role_creation_enabled"></a> [grafana\_role\_creation\_enabled](#input\_grafana\_role\_creation\_enabled) | Create an IAM role that Amazon Managed Grafana can assume to read this cluster's telemetry: query access to the AMP workspace and read access to the Container Insights log groups. No Grafana workspace is created - provisioning one requires IAM Identity Center wiring that belongs at the organization level, not in a cluster module. | `bool` | `false` | no |
| <a name="input_grafana_service_account"></a> [grafana\_service\_account](#input\_grafana\_service\_account) | Service account Grafana runs as. The Pod Identity association binds the Amazon Managed Prometheus read role to this name, so Grafana's SigV4 datasource signs with credentials it never stores. | `string` | `"ravion-grafana"` | no |
| <a name="input_grafana_source_account_id"></a> [grafana\_source\_account\_id](#input\_grafana\_source\_account\_id) | AWS account whose Grafana workspaces may assume the read role, enforced with an aws:SourceAccount condition. When null, this account is used. Set it to the account that hosts the Grafana workspace when that differs from the cluster's account. | `string` | `null` | no |
| <a name="input_karpenter_chart_version"></a> [karpenter\_chart\_version](#input\_karpenter\_chart\_version) | Version of the Karpenter Helm chart (and karpenter-crd chart) to install. | `string` | `"1.14.0"` | no |
| <a name="input_karpenter_controller_namespace"></a> [karpenter\_controller\_namespace](#input\_karpenter\_controller\_namespace) | Kubernetes namespace where the Karpenter controller is installed. | `string` | `"kube-system"` | no |
| <a name="input_karpenter_controller_service_account"></a> [karpenter\_controller\_service\_account](#input\_karpenter\_controller\_service\_account) | Kubernetes service account name for the Karpenter controller. | `string` | `"karpenter"` | no |
| <a name="input_karpenter_default_node_pool"></a> [karpenter\_default\_node\_pool](#input\_karpenter\_default\_node\_pool) | Settings for the default NodePool: allowed capacity types (on-demand/spot), EC2 instance categories, CPU architectures, total vCPU limit, and node expiry. | <pre>object({<br/>    capacity_types      = optional(list(string), ["on-demand", "spot"])<br/>    instance_categories = optional(list(string), ["c", "m", "r"])<br/>    architectures       = optional(list(string), ["amd64"])<br/>    cpu_limit           = optional(number, 100)<br/>    expire_after        = optional(string, "720h")<br/>  })</pre> | `{}` | no |
| <a name="input_karpenter_default_node_pool_creation_enabled"></a> [karpenter\_default\_node\_pool\_creation\_enabled](#input\_karpenter\_default\_node\_pool\_creation\_enabled) | Create a general-purpose default NodePool and EC2NodeClass so Karpenter can provision nodes out of the box. Disable to manage NodePools yourself. | `bool` | `true` | no |
| <a name="input_karpenter_enabled"></a> [karpenter\_enabled](#input\_karpenter\_enabled) | Install Karpenter end to end: controller and node IAM roles, Pod Identity association, instance profile, interruption queue, EventBridge rules, the controller Helm charts, and (optionally) a default NodePool. | `bool` | `true` | no |
| <a name="input_karpenter_helm_values"></a> [karpenter\_helm\_values](#input\_karpenter\_helm\_values) | Additional YAML documents merged into the Karpenter Helm chart values, after the values this module derives (cluster name, interruption queue, service account). Later entries win. | `list(string)` | `[]` | no |
| <a name="input_karpenter_interruption_queue_message_retention_seconds"></a> [karpenter\_interruption\_queue\_message\_retention\_seconds](#input\_karpenter\_interruption\_queue\_message\_retention\_seconds) | Message retention for the Karpenter interruption queue. | `number` | `300` | no |
| <a name="input_karpenter_interruption_queue_name"></a> [karpenter\_interruption\_queue\_name](#input\_karpenter\_interruption\_queue\_name) | Name for the SQS interruption queue. When null, defaults to 'karpenter-<cluster\_name>'. | `string` | `null` | no |
| <a name="input_karpenter_node_role_additional_managed_policy_arns"></a> [karpenter\_node\_role\_additional\_managed\_policy\_arns](#input\_karpenter\_node\_role\_additional\_managed\_policy\_arns) | Extra managed policy ARNs to attach to the Karpenter-launched node role. | `list(string)` | `[]` | no |
| <a name="input_kube_state_metrics_chart_version"></a> [kube\_state\_metrics\_chart\_version](#input\_kube\_state\_metrics\_chart\_version) | Version of the prometheus-community/kube-state-metrics Helm chart to install. | `string` | `"8.3.0"` | no |
| <a name="input_kube_state_metrics_enabled"></a> [kube\_state\_metrics\_enabled](#input\_kube\_state\_metrics\_enabled) | Install kube-state-metrics alongside the collector. It is the source of every kube\_* series in the allow-list (replica counts, restart reasons, pod phase, node conditions), so turning it off leaves only cAdvisor and kubelet metrics. Only takes effect when metrics\_enabled is true. | `bool` | `true` | no |
| <a name="input_kube_state_metrics_helm_values"></a> [kube\_state\_metrics\_helm\_values](#input\_kube\_state\_metrics\_helm\_values) | Extra YAML documents merged into the kube-state-metrics chart values (later entries win), e.g. a narrowed 'collectors' list or a private image registry. | `list(string)` | `[]` | no |
| <a name="input_load_balancer_deletion_protection_enabled"></a> [load\_balancer\_deletion\_protection\_enabled](#input\_load\_balancer\_deletion\_protection\_enabled) | Enable deletion protection on the shared load balancers. | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | How long logs are queryable. Enforced by Loki's compactor, which deletes chunks whose retention has expired; the created bucket additionally carries a lifecycle expiration a week later as a backstop for anything the compactor orphans. | `number` | `30` | no |
| <a name="input_logs_cloudwatch"></a> [logs\_cloudwatch](#input\_logs\_cloudwatch) | CloudWatch Logs settings. The default log group is /ravion/eks/<cluster>, one stream per pod named <namespace>/<pod>/<container>. | <pre>object({<br/>    retention_days = optional(number)<br/>    log_group_name = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_datadog"></a> [logs\_datadog](#input\_logs\_datadog) | Datadog logs: the site (datadoghq.com, datadoghq.eu, ...) and a Secrets Manager ARN holding the API key. Shared with metrics\_datadog when both signals pick Datadog. | <pre>object({<br/>    site               = optional(string)<br/>    api_key_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_excluded_namespaces"></a> [logs\_excluded\_namespaces](#input\_logs\_excluded\_namespaces) | Namespaces no log collector reads from. Applies to every logs provider: Alloy drops them at discovery, the OpenTelemetry collector never opens their files. Ravion's own namespace is excluded by default so the collectors do not tail themselves into a loop. | `list(string)` | <pre>[<br/>  "kube-system",<br/>  "kube-node-lease",<br/>  "amazon-cloudwatch",<br/>  "ravion-operator",<br/>  "ravion-beacon"<br/>]</pre> | no |
| <a name="input_logs_grafana_cloud"></a> [logs\_grafana\_cloud](#input\_logs\_grafana\_cloud) | Grafana Cloud Logs: the Loki push URL, the numeric user/tenant id, a Secrets Manager ARN holding the access token, and (optionally) the stack URL used to build the 'Open in Grafana' link. Alloy writes here with basic auth, alongside any other loki-family destination. | <pre>object({<br/>    url              = optional(string)<br/>    user             = optional(string)<br/>    token_secret_arn = optional(string)<br/>    stack_url        = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_loki"></a> [logs\_loki](#input\_logs\_loki) | In-cluster Loki settings: how long logs stay queryable, an existing bucket to store chunks in, and the local working volume. Falls back to log\_retention\_days / loki\_s3\_bucket\_name / loki\_persistence\_* when a field is null. | <pre>object({<br/>    retention_days      = optional(number)<br/>    s3_bucket_name      = optional(string)<br/>    persistence_enabled = optional(bool)<br/>    persistence_size    = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_namespace"></a> [logs\_namespace](#input\_logs\_namespace) | Kubernetes namespace for Loki and Alloy. Null uses observability\_namespace (default ravion-operator). Created if missing. | `string` | `null` | no |
| <a name="input_logs_new_relic"></a> [logs\_new\_relic](#input\_logs\_new\_relic) | New Relic logs: region (us or eu, deciding the OTLP endpoint) and a Secrets Manager ARN holding the license key. | <pre>object({<br/>    region                 = optional(string)<br/>    license_key_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_opensearch"></a> [logs\_opensearch](#input\_logs\_opensearch) | Amazon OpenSearch Service: the domain endpoint (https://...) and the index prefix. Requests are signed with SigV4 from the collector's Pod Identity role, so the domain's access policy or its fine-grained role mapping has to name logs\_opensearch\_role\_arn - the module cannot do that from outside the domain. | <pre>object({<br/>    endpoint     = optional(string)<br/>    index_prefix = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_otlp"></a> [logs\_otlp](#input\_logs\_otlp) | Any OTLP/HTTP log receiver: the endpoint, and optionally a Secrets Manager ARN holding the value of an Authorization header the collector sends with every request. | <pre>object({<br/>    endpoint           = optional(string)<br/>    headers_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_logs_providers"></a> [logs\_providers](#input\_logs\_providers) | Where container logs go. Any combination of: loki (in-cluster store on S3, renders in Ravion), cloudwatch (CloudWatch Logs, renders in Ravion), grafana\_cloud, datadog, new\_relic, opensearch, splunk, otlp. An empty list turns logs off entirely — no collector, no store. | `list(string)` | <pre>[<br/>  "loki"<br/>]</pre> | no |
| <a name="input_logs_splunk"></a> [logs\_splunk](#input\_logs\_splunk) | Splunk HTTP Event Collector: the HEC URL, a Secrets Manager ARN holding the token, and the target index. | <pre>object({<br/>    hec_url              = optional(string)<br/>    hec_token_secret_arn = optional(string)<br/>    index                = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_loki_chart_version"></a> [loki\_chart\_version](#input\_loki\_chart\_version) | Version of the grafana/loki Helm chart to install. | `string` | `"7.3.0"` | no |
| <a name="input_loki_helm_values"></a> [loki\_helm\_values](#input\_loki\_helm\_values) | Extra YAML documents merged into the grafana/loki chart values, after the values this module derives (later entries win). The route to simple-scalable mode, caches, tolerations, or a private image registry. | `list(string)` | `[]` | no |
| <a name="input_loki_persistence_enabled"></a> [loki\_persistence\_enabled](#input\_loki\_persistence\_enabled) | Give Loki a PersistentVolumeClaim for its write-ahead log and index cache. Off by default because it needs a working StorageClass - on a Ravion cluster that means ebs\_csi\_driver\_enabled - and an unschedulable PVC is a worse first run than an ephemeral one. With it off, chunks still land in S3; what is lost on a restart is the few minutes of logs not yet flushed. | `bool` | `false` | no |
| <a name="input_loki_persistence_size"></a> [loki\_persistence\_size](#input\_loki\_persistence\_size) | Size of Loki's local working volume, which holds the write-ahead log, the compactor's working directory, and the index cache - not the logs themselves, which are in S3. Becomes the PersistentVolumeClaim size when loki\_persistence\_enabled is true, and the emptyDir size limit when it is false. | `string` | `"10Gi"` | no |
| <a name="input_loki_resources"></a> [loki\_resources](#input\_loki\_resources) | Resource requests and limits for the Loki pod. Sized for a small cluster in single-binary mode; raise the memory limit before raising anything else, because query fan-out over many streams is what pushes Loki over. Null limits are omitted. | <pre>object({<br/>    cpu_request    = optional(string, "200m")<br/>    memory_request = optional(string, "512Mi")<br/>    cpu_limit      = optional(string)<br/>    memory_limit   = optional(string, "1Gi")<br/>  })</pre> | `{}` | no |
| <a name="input_loki_s3_bucket_name"></a> [loki\_s3\_bucket\_name](#input\_loki\_s3\_bucket\_name) | Existing S3 bucket to store log chunks and the index in. When null, the module creates 'ravion-loki-<cluster>-<account>'. Bring your own to control naming, encryption, or lifecycle policy yourself - the module then manages neither the bucket nor its retention. | `string` | `null` | no |
| <a name="input_loki_service_account"></a> [loki\_service\_account](#input\_loki\_service\_account) | Service account Loki runs as. The Pod Identity association binds the S3 role to this name, so the chart and the association are driven from this single value. | `string` | `"ravion-loki"` | no |
| <a name="input_metrics_additional_allowlist"></a> [metrics\_additional\_allowlist](#input\_metrics\_additional\_allowlist) | Extra metric-name regexes appended to the curated allow-list on every scrape job. Anything not matched by the base list or by these is dropped before it enters collector memory, so this is the only way to widen what reaches AMP. Entries are alternation branches in a fully anchored regex - 'my\_app\_.*', not '.*my\_app.*'. | `list(string)` | `[]` | no |
| <a name="input_metrics_amp"></a> [metrics\_amp](#input\_metrics\_amp) | Amazon Managed Prometheus: an existing workspace to write into, the region it lives in, and the alias for a created one. Falls back to amp\_workspace\_id / amp\_region / amp\_alias. | <pre>object({<br/>    workspace_id = optional(string)<br/>    region       = optional(string)<br/>    alias        = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_cloudwatch"></a> [metrics\_cloudwatch](#input\_metrics\_cloudwatch) | CloudWatch Container Insights. Application Signals auto-instrumentation is OFF unless application\_signals\_enabled is true: with it on, the add-on's Auto-Monitor webhook injects the AWS OpenTelemetry agent into workloads and restarts their pods, which is exactly the behaviour that used to be silently on. Falls back to cloudwatch\_observability\_addon\_version / cloudwatch\_observability\_addon\_configuration\_values. | <pre>object({<br/>    enhanced_observability_enabled = optional(bool)<br/>    application_signals_enabled    = optional(bool)<br/>    application_signals_namespaces = optional(list(string))<br/>    addon_version                  = optional(string)<br/>    addon_configuration_values     = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_datadog"></a> [metrics\_datadog](#input\_metrics\_datadog) | Datadog metrics: the site and a Secrets Manager ARN holding the API key. Shared with logs\_datadog when both signals pick Datadog. | <pre>object({<br/>    site               = optional(string)<br/>    api_key_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_grafana_cloud"></a> [metrics\_grafana\_cloud](#input\_metrics\_grafana\_cloud) | Grafana Cloud Metrics: the Prometheus remote-write URL, the numeric instance/user id, a Secrets Manager ARN holding the token, and (optionally) the stack URL for the 'Open in Grafana' link. | <pre>object({<br/>    url              = optional(string)<br/>    user             = optional(string)<br/>    token_secret_arn = optional(string)<br/>    stack_url        = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_namespace"></a> [metrics\_namespace](#input\_metrics\_namespace) | Kubernetes namespace for metrics components. Null uses observability\_namespace (default ravion-operator). Created if missing. | `string` | `null` | no |
| <a name="input_metrics_new_relic"></a> [metrics\_new\_relic](#input\_metrics\_new\_relic) | New Relic metrics: region (us or eu) and a Secrets Manager ARN holding the license key. | <pre>object({<br/>    region                 = optional(string)<br/>    license_key_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_otlp"></a> [metrics\_otlp](#input\_metrics\_otlp) | Any OTLP/HTTP metrics receiver: the endpoint, and optionally a Secrets Manager ARN holding the value of an Authorization header. | <pre>object({<br/>    endpoint           = optional(string)<br/>    headers_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_prometheus"></a> [metrics\_prometheus](#input\_metrics\_prometheus) | Prometheus running in the cluster, with the remote-write receiver on and a PersistentVolume behind it. Set endpoint to point at a Prometheus you already run, and the module installs nothing and only remote-writes to it. Installing needs a working StorageClass, which on a Ravion cluster means ebs\_csi\_driver\_enabled. | <pre>object({<br/>    retention_days = optional(number)<br/>    storage_size   = optional(string)<br/>    endpoint       = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_metrics_providers"></a> [metrics\_providers](#input\_metrics\_providers) | Metric destinations: amp, prometheus (in-cluster, queried through EKS service proxy over SSM), cloudwatch, grafana\_cloud, datadog, new\_relic, otlp. Empty disables metrics. | `list(string)` | <pre>[<br/>  "amp"<br/>]</pre> | no |
| <a name="input_node_subnet_ids"></a> [node\_subnet\_ids](#input\_node\_subnet\_ids) | Private subnet IDs (node\_subnet\_ids output of the compute/eks stack). Used by the default Karpenter NodePool to launch nodes and by internal load balancers. Required when Karpenter's default NodePool, the private ALB, or the private NLB is enabled. | `list(string)` | `null` | no |
| <a name="input_observability_namespace"></a> [observability\_namespace](#input\_observability\_namespace) | Shared namespace for collectors, stores and vendor credentials. Null defaults to ravion-operator to preserve existing release and storage identity. Created if missing. | `string` | `null` | no |
| <a name="input_observed_namespaces"></a> [observed\_namespaces](#input\_observed\_namespaces) | Additional observation namespaces. Unioned with workload\_namespaces for retained namespace bootstrap and Helm inventory get/list Secrets grants to ravion:readers. RBAC cannot restrict Secret listing by Helm labels; readers can read all Secrets in each selected namespace. | `list(string)` | `[]` | no |
| <a name="input_otel_collector_chart_version"></a> [otel\_collector\_chart\_version](#input\_otel\_collector\_chart\_version) | Version of the community opentelemetry-collector Helm chart used to run the collector. | `string` | `"0.169.0"` | no |
| <a name="input_otel_collector_command_name"></a> [otel\_collector\_command\_name](#input\_otel\_collector\_command\_name) | Binary the metrics collector container runs, as the chart's command.name (it renders '/<name>'). When null it follows the chosen image: 'awscollector' for the AWS Distro, 'otelcol-contrib' for contrib. | `string` | `null` | no |
| <a name="input_otel_collector_helm_values"></a> [otel\_collector\_helm\_values](#input\_otel\_collector\_helm\_values) | Extra YAML documents merged into the opentelemetry-collector chart values, after the values this module derives (later entries win). The route to tolerations, node selectors, extra scrape jobs, or a second exporter. | `list(string)` | `[]` | no |
| <a name="input_otel_collector_image_repository"></a> [otel\_collector\_image\_repository](#input\_otel\_collector\_image\_repository) | Metrics collector image. When null the module chooses: the AWS Distro for OpenTelemetry (public.ecr.aws/aws-observability/aws-otel-collector) for an AMP-only or CloudWatch-only selection, and the upstream contrib distribution when a vendor provider is selected, because the AWS Distro does not ship the datadog exporter or the basicauth extension. Point this at a private mirror if the cluster cannot reach the registry. | `string` | `null` | no |
| <a name="input_otel_collector_image_tag"></a> [otel\_collector\_image\_tag](#input\_otel\_collector\_image\_tag) | Tag of the metrics collector image. When null it follows the image the module chose: v0.49.0 for the AWS Distro, otel\_contrib\_image\_tag for contrib. | `string` | `null` | no |
| <a name="input_otel_collector_resources"></a> [otel\_collector\_resources](#input\_otel\_collector\_resources) | Resource requests and limits for the collector pod. A memory limit is set by default because the collector's memory\_limiter processor sizes itself as a percentage of the container limit - with no limit it would measure against the whole node. Null limits are omitted. | <pre>object({<br/>    cpu_request    = optional(string, "100m")<br/>    memory_request = optional(string, "256Mi")<br/>    cpu_limit      = optional(string)<br/>    memory_limit   = optional(string, "512Mi")<br/>  })</pre> | `{}` | no |
| <a name="input_otel_collector_service_account"></a> [otel\_collector\_service\_account](#input\_otel\_collector\_service\_account) | Service account the collector runs as. The Pod Identity association binds the AMP remote-write role to this name, so the chart and the association are driven from this single value. | `string` | `"ravion-otel-collector"` | no |
| <a name="input_otel_contrib_command_name"></a> [otel\_contrib\_command\_name](#input\_otel\_contrib\_command\_name) | Binary the contrib collector container runs, as the chart's command.name (it renders '/<name>'). | `string` | `"otelcol-contrib"` | no |
| <a name="input_otel_contrib_image_repository"></a> [otel\_contrib\_image\_repository](#input\_otel\_contrib\_image\_repository) | Image for collectors that need vendor exporters (datadog, splunk\_hec, opensearch, awscloudwatchlogs). The AWS Distro does not ship them, so the log collector — and the metrics collector, when a vendor provider is selected — runs the upstream contrib distribution instead. | `string` | `"docker.io/otel/opentelemetry-collector-contrib"` | no |
| <a name="input_otel_contrib_image_tag"></a> [otel\_contrib\_image\_tag](#input\_otel\_contrib\_image\_tag) | Tag of the contrib collector image. | `string` | `"0.137.0"` | no |
| <a name="input_otel_logs_collector_helm_values"></a> [otel\_logs\_collector\_helm\_values](#input\_otel\_logs\_collector\_helm\_values) | Extra YAML documents merged into the opentelemetry-collector chart values for the log collector (later entries win). | `list(string)` | `[]` | no |
| <a name="input_otel_logs_collector_resources"></a> [otel\_logs\_collector\_resources](#input\_otel\_logs\_collector\_resources) | Resource requests and limits for each log collector pod. It runs on every node, so this is multiplied by the node count. A memory limit is set by default because the collector's memory\_limiter processor sizes itself as a percentage of the container limit. | <pre>object({<br/>    cpu_request    = optional(string, "100m")<br/>    memory_request = optional(string, "128Mi")<br/>    cpu_limit      = optional(string)<br/>    memory_limit   = optional(string, "512Mi")<br/>  })</pre> | `{}` | no |
| <a name="input_otel_logs_collector_service_account"></a> [otel\_logs\_collector\_service\_account](#input\_otel\_logs\_collector\_service\_account) | Service account the log collector runs as. The Pod Identity association that lets it write to CloudWatch Logs or sign OpenSearch requests binds to this name. | `string` | `"ravion-otel-logs-collector"` | no |
| <a name="input_private_alb_access_logs_bucket_arn"></a> [private\_alb\_access\_logs\_bucket\_arn](#input\_private\_alb\_access\_logs\_bucket\_arn) | The ARN of an existing S3 bucket for private ALB access logs. | `string` | `null` | no |
| <a name="input_private_alb_access_logs_enabled"></a> [private\_alb\_access\_logs\_enabled](#input\_private\_alb\_access\_logs\_enabled) | Enable access logging for the private ALB. | `bool` | `false` | no |
| <a name="input_private_alb_certificate_arns"></a> [private\_alb\_certificate\_arns](#input\_private\_alb\_certificate\_arns) | ACM certificate ARNs for the private ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI. | `list(string)` | `[]` | no |
| <a name="input_private_alb_creation_enabled"></a> [private\_alb\_creation\_enabled](#input\_private\_alb\_creation\_enabled) | Create a shared private (internal) Application Load Balancer that workloads attach to via TargetGroupBinding. | `bool` | `false` | no |
| <a name="input_private_alb_https_enabled"></a> [private\_alb\_https\_enabled](#input\_private\_alb\_https\_enabled) | Enable HTTPS listener on the private ALB. | `bool` | `false` | no |
| <a name="input_private_alb_idle_timeout"></a> [private\_alb\_idle\_timeout](#input\_private\_alb\_idle\_timeout) | The idle timeout for the private ALB in seconds. | `number` | `60` | no |
| <a name="input_private_alb_ingress_cidr_blocks"></a> [private\_alb\_ingress\_cidr\_blocks](#input\_private\_alb\_ingress\_cidr\_blocks) | IPv4 CIDR blocks allowed to access the private ALB. | `list(string)` | <pre>[<br/>  "10.0.0.0/8",<br/>  "172.16.0.0/12",<br/>  "192.168.0.0/16"<br/>]</pre> | no |
| <a name="input_private_alb_ingress_ipv6_cidr_blocks"></a> [private\_alb\_ingress\_ipv6\_cidr\_blocks](#input\_private\_alb\_ingress\_ipv6\_cidr\_blocks) | IPv6 CIDR blocks allowed to access the private ALB. Defaults to no IPv6 ingress; RFC1918 has no IPv6 equivalent. | `list(string)` | `[]` | no |
| <a name="input_private_alb_ingress_security_group_ids"></a> [private\_alb\_ingress\_security\_group\_ids](#input\_private\_alb\_ingress\_security\_group\_ids) | Security group IDs whose members are allowed to access the private ALB. Useful for sources without static CIDRs, such as CloudFront VPC origins. | `list(string)` | `[]` | no |
| <a name="input_private_alb_ssl_policy"></a> [private\_alb\_ssl\_policy](#input\_private\_alb\_ssl\_policy) | The SSL policy for the private ALB HTTPS listener. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_private_nlb_access_logs_bucket_arn"></a> [private\_nlb\_access\_logs\_bucket\_arn](#input\_private\_nlb\_access\_logs\_bucket\_arn) | The ARN of an existing S3 bucket for private NLB access logs. | `string` | `null` | no |
| <a name="input_private_nlb_access_logs_enabled"></a> [private\_nlb\_access\_logs\_enabled](#input\_private\_nlb\_access\_logs\_enabled) | Enable access logging for the private NLB. | `bool` | `false` | no |
| <a name="input_private_nlb_creation_enabled"></a> [private\_nlb\_creation\_enabled](#input\_private\_nlb\_creation\_enabled) | Create a shared private (internal) Network Load Balancer that workloads attach to via TargetGroupBinding. | `bool` | `false` | no |
| <a name="input_private_nlb_cross_zone_load_balancing_enabled"></a> [private\_nlb\_cross\_zone\_load\_balancing\_enabled](#input\_private\_nlb\_cross\_zone\_load\_balancing\_enabled) | Enable cross-zone load balancing for the private NLB. | `bool` | `false` | no |
| <a name="input_private_nlb_elastic_ip_allocation_ids"></a> [private\_nlb\_elastic\_ip\_allocation\_ids](#input\_private\_nlb\_elastic\_ip\_allocation\_ids) | A list of Elastic IP allocation IDs for the private NLB, one per subnet. | `list(string)` | `[]` | no |
| <a name="input_private_nlb_elastic_ips_enabled"></a> [private\_nlb\_elastic\_ips\_enabled](#input\_private\_nlb\_elastic\_ips\_enabled) | Enable static IP addresses for the private NLB using Elastic IPs. | `bool` | `false` | no |
| <a name="input_private_nlb_security_group_ids"></a> [private\_nlb\_security\_group\_ids](#input\_private\_nlb\_security\_group\_ids) | A list of additional security group IDs to attach to the private NLB. | `list(string)` | `[]` | no |
| <a name="input_prometheus_chart_version"></a> [prometheus\_chart\_version](#input\_prometheus\_chart\_version) | Version of the prometheus-community/prometheus Helm chart installed for the in-cluster prometheus provider. | `string` | `"27.44.0"` | no |
| <a name="input_prometheus_helm_values"></a> [prometheus\_helm\_values](#input\_prometheus\_helm\_values) | Extra YAML documents merged into the prometheus chart values, after the values this module derives (later entries win). The route to alerting rules, extra scrape jobs, or a private image registry. | `list(string)` | `[]` | no |
| <a name="input_public_alb_access_logs_bucket_arn"></a> [public\_alb\_access\_logs\_bucket\_arn](#input\_public\_alb\_access\_logs\_bucket\_arn) | The ARN of an existing S3 bucket for public ALB access logs. | `string` | `null` | no |
| <a name="input_public_alb_access_logs_enabled"></a> [public\_alb\_access\_logs\_enabled](#input\_public\_alb\_access\_logs\_enabled) | Enable access logging for the public ALB. | `bool` | `false` | no |
| <a name="input_public_alb_certificate_arns"></a> [public\_alb\_certificate\_arns](#input\_public\_alb\_certificate\_arns) | ACM certificate ARNs for the public ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI. | `list(string)` | `[]` | no |
| <a name="input_public_alb_creation_enabled"></a> [public\_alb\_creation\_enabled](#input\_public\_alb\_creation\_enabled) | Create a shared public (internet-facing) Application Load Balancer that workloads attach to via TargetGroupBinding. | `bool` | `false` | no |
| <a name="input_public_alb_https_enabled"></a> [public\_alb\_https\_enabled](#input\_public\_alb\_https\_enabled) | Enable HTTPS listener on the public ALB. | `bool` | `false` | no |
| <a name="input_public_alb_idle_timeout"></a> [public\_alb\_idle\_timeout](#input\_public\_alb\_idle\_timeout) | The idle timeout for the public ALB in seconds. | `number` | `60` | no |
| <a name="input_public_alb_ingress_cidr_blocks"></a> [public\_alb\_ingress\_cidr\_blocks](#input\_public\_alb\_ingress\_cidr\_blocks) | IPv4 CIDR blocks allowed to access the public ALB. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_public_alb_ingress_ipv6_cidr_blocks"></a> [public\_alb\_ingress\_ipv6\_cidr\_blocks](#input\_public\_alb\_ingress\_ipv6\_cidr\_blocks) | IPv6 CIDR blocks allowed to access the public ALB. | `list(string)` | <pre>[<br/>  "::/0"<br/>]</pre> | no |
| <a name="input_public_alb_ingress_security_group_ids"></a> [public\_alb\_ingress\_security\_group\_ids](#input\_public\_alb\_ingress\_security\_group\_ids) | Security group IDs whose members are allowed to access the public ALB. | `list(string)` | `[]` | no |
| <a name="input_public_alb_ssl_policy"></a> [public\_alb\_ssl\_policy](#input\_public\_alb\_ssl\_policy) | The SSL policy for the public ALB HTTPS listener. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_public_alb_web_acl_arn"></a> [public\_alb\_web\_acl\_arn](#input\_public\_alb\_web\_acl\_arn) | The ARN of a WAFv2 Web ACL to associate with the public ALB. | `string` | `null` | no |
| <a name="input_public_nlb_access_logs_bucket_arn"></a> [public\_nlb\_access\_logs\_bucket\_arn](#input\_public\_nlb\_access\_logs\_bucket\_arn) | The ARN of an existing S3 bucket for public NLB access logs. | `string` | `null` | no |
| <a name="input_public_nlb_access_logs_enabled"></a> [public\_nlb\_access\_logs\_enabled](#input\_public\_nlb\_access\_logs\_enabled) | Enable access logging for the public NLB. | `bool` | `false` | no |
| <a name="input_public_nlb_creation_enabled"></a> [public\_nlb\_creation\_enabled](#input\_public\_nlb\_creation\_enabled) | Create a shared public (internet-facing) Network Load Balancer that workloads attach to via TargetGroupBinding. | `bool` | `false` | no |
| <a name="input_public_nlb_cross_zone_load_balancing_enabled"></a> [public\_nlb\_cross\_zone\_load\_balancing\_enabled](#input\_public\_nlb\_cross\_zone\_load\_balancing\_enabled) | Enable cross-zone load balancing for the public NLB. | `bool` | `false` | no |
| <a name="input_public_nlb_elastic_ip_allocation_ids"></a> [public\_nlb\_elastic\_ip\_allocation\_ids](#input\_public\_nlb\_elastic\_ip\_allocation\_ids) | A list of Elastic IP allocation IDs for the public NLB, one per subnet. | `list(string)` | `[]` | no |
| <a name="input_public_nlb_elastic_ips_enabled"></a> [public\_nlb\_elastic\_ips\_enabled](#input\_public\_nlb\_elastic\_ips\_enabled) | Enable static IP addresses for the public NLB using Elastic IPs. | `bool` | `false` | no |
| <a name="input_public_nlb_security_group_ids"></a> [public\_nlb\_security\_group\_ids](#input\_public\_nlb\_security\_group\_ids) | A list of additional security group IDs to attach to the public NLB. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs for internet-facing load balancers (public\_subnet\_ids output of the compute/eks stack). Required when the public ALB or public NLB is enabled. | `list(string)` | `[]` | no |
| <a name="input_ravion_runner_role_arn"></a> [ravion\_runner\_role\_arn](#input\_ravion\_runner\_role\_arn) | IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion\_runner\_role\_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| <a name="input_scrape_interval_seconds"></a> [scrape\_interval\_seconds](#input\_scrape\_interval\_seconds) | How often the collector scrapes each target. Sample count - and therefore AMP cost - scales inversely with this, so lengthening it is the first cost lever. | `number` | `60` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags applied to EC2 instances launched by the default Karpenter NodePool. | `map(string)` | `{}` | no |
| <a name="input_workload_namespaces"></a> [workload\_namespaces](#input\_workload\_namespaces) | Deployment/workload namespaces to bootstrap. Unioned with observed\_namespaces for namespace-scoped get/list Secrets so readers can inspect Helm inventory and drift. This grants access to every Secret in those namespaces. | `list(string)` | `[]` | no |
| <a name="input_workload_namespaces_creation_enabled"></a> [workload\_namespaces\_creation\_enabled](#input\_workload\_namespaces\_creation\_enabled) | Create missing workload and observed namespaces. Existing namespaces are reused without adoption; created namespaces are retained on removal or uninstall. Disabling creation preserves namespace-scoped Helm inventory Secret read grants. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alloy_chart_version"></a> [alloy\_chart\_version](#output\_alloy\_chart\_version) | Installed version of the grafana/alloy Helm chart (null if logs are disabled). |
| <a name="output_amp_query_endpoint"></a> [amp\_query\_endpoint](#output\_amp\_query\_endpoint) | Prometheus-compatible query base URL for the workspace (null if metrics are disabled). Use it as-is as a Grafana datasource URL; append /api/v1/query for the HTTP API. |
| <a name="output_amp_region"></a> [amp\_region](#output\_amp\_region) | Region the AMP workspace lives in (null if metrics are disabled). May differ from the cluster's region when amp\_region is set. |
| <a name="output_amp_remote_write_endpoint"></a> [amp\_remote\_write\_endpoint](#output\_amp\_remote\_write\_endpoint) | SigV4-signed remote-write URL the collector posts to (null if metrics are disabled). |
| <a name="output_amp_remote_write_role_arn"></a> [amp\_remote\_write\_role\_arn](#output\_amp\_remote\_write\_role\_arn) | ARN of the collector's Pod Identity role, scoped to aps:RemoteWrite on this workspace alone (null if metrics are disabled). |
| <a name="output_amp_workspace_arn"></a> [amp\_workspace\_arn](#output\_amp\_workspace\_arn) | ARN of the AMP workspace (null if metrics are disabled). What a query role or cross-account grant is scoped to. |
| <a name="output_amp_workspace_id"></a> [amp\_workspace\_id](#output\_amp\_workspace\_id) | Amazon Managed Prometheus workspace the collector writes to (null if metrics are disabled). The created workspace, or the one passed as amp\_workspace\_id. |
| <a name="output_cloudwatch_application_signals_namespaces"></a> [cloudwatch\_application\_signals\_namespaces](#output\_cloudwatch\_application\_signals\_namespaces) | Namespaces Application Signals auto-instrumentation was asked for. The add-on's cluster-wide Auto-Monitor stays OFF when this is non-empty: annotate these namespaces with instrumentation.opentelemetry.io/inject-* to instrument exactly them. Empty list when Application Signals is off or when it was enabled cluster-wide. |
| <a name="output_cloudwatch_observability_addon_version"></a> [cloudwatch\_observability\_addon\_version](#output\_cloudwatch\_observability\_addon\_version) | Resolved version of the amazon-cloudwatch-observability EKS add-on (null unless cloudwatch is in logs\_providers or metrics\_providers). |
| <a name="output_cloudwatch_observability_role_arn"></a> [cloudwatch\_observability\_role\_arn](#output\_cloudwatch\_observability\_role\_arn) | ARN of the CloudWatch Observability add-on Pod Identity role (null unless the add-on is installed). |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | EKS cluster ARN used to resolve SSM access and observability without an Operator agent identifier. |
| <a name="output_ebs_csi_addon_version"></a> [ebs\_csi\_addon\_version](#output\_ebs\_csi\_addon\_version) | Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled). |
| <a name="output_ebs_csi_role_arn"></a> [ebs\_csi\_role\_arn](#output\_ebs\_csi\_role\_arn) | ARN of the EBS CSI driver Pod Identity role (null if disabled). |
| <a name="output_eso_chart_version"></a> [eso\_chart\_version](#output\_eso\_chart\_version) | Installed version of the external-secrets Helm chart (null if disabled). |
| <a name="output_eso_namespace"></a> [eso\_namespace](#output\_eso\_namespace) | Kubernetes namespace where the External Secrets Operator is installed (null if disabled). |
| <a name="output_eso_parameter_store_store_name"></a> [eso\_parameter\_store\_store\_name](#output\_eso\_parameter\_store\_store\_name) | Name of the cluster-scoped AWS SSM Parameter Store store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for SSM parameters (null if disabled). |
| <a name="output_eso_role_arn"></a> [eso\_role\_arn](#output\_eso\_role\_arn) | ARN of the External Secrets Operator Pod Identity role (null if disabled). |
| <a name="output_eso_secrets_manager_store_name"></a> [eso\_secrets\_manager\_store\_name](#output\_eso\_secrets\_manager\_store\_name) | Name of the cluster-scoped AWS Secrets Manager store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for Secrets Manager secrets (null if disabled). |
| <a name="output_grafana_amp_role_arn"></a> [grafana\_amp\_role\_arn](#output\_grafana\_amp\_role\_arn) | ARN of the in-cluster Grafana's Pod Identity role for querying the AMP workspace (null when Grafana or metrics are disabled). Distinct from grafana\_role\_arn, which is for Amazon Managed Grafana reaching in from outside. |
| <a name="output_grafana_cloud_logs_query_url"></a> [grafana\_cloud\_logs\_query\_url](#output\_grafana\_cloud\_logs\_query\_url) | Grafana Cloud Loki query base URL, derived from the push URL (null unless grafana\_cloud is selected). |
| <a name="output_grafana_cloud_metrics_query_url"></a> [grafana\_cloud\_metrics\_query\_url](#output\_grafana\_cloud\_metrics\_query\_url) | Grafana Cloud Prometheus query base URL, derived from the remote-write URL (null unless grafana\_cloud is in metrics\_providers). |
| <a name="output_grafana_namespace"></a> [grafana\_namespace](#output\_grafana\_namespace) | Kubernetes namespace the in-cluster Grafana is installed into (null if disabled). |
| <a name="output_grafana_role_arn"></a> [grafana\_role\_arn](#output\_grafana\_role\_arn) | ARN of the role Amazon Managed Grafana assumes to query the AMP workspace and read the Container Insights log groups (null if disabled). |
| <a name="output_grafana_service"></a> [grafana\_service](#output\_grafana\_service) | In-cluster Grafana Service (null if disabled). No ingress is created: reach it with 'kubectl -n <namespace> port-forward svc/<service> 3000:80', or add an ingress through grafana\_helm\_values. |
| <a name="output_karpenter_chart_version"></a> [karpenter\_chart\_version](#output\_karpenter\_chart\_version) | Installed version of the Karpenter Helm chart (null if disabled). |
| <a name="output_karpenter_controller_role_arn"></a> [karpenter\_controller\_role\_arn](#output\_karpenter\_controller\_role\_arn) | ARN of the Karpenter controller IAM role (null if disabled). |
| <a name="output_karpenter_default_node_pool_release"></a> [karpenter\_default\_node\_pool\_release](#output\_karpenter\_default\_node\_pool\_release) | Helm release name of the default NodePool chart (null if disabled). |
| <a name="output_karpenter_interruption_queue_name"></a> [karpenter\_interruption\_queue\_name](#output\_karpenter\_interruption\_queue\_name) | Name of the SQS interruption queue (null if disabled). |
| <a name="output_karpenter_namespace"></a> [karpenter\_namespace](#output\_karpenter\_namespace) | Kubernetes namespace where the Karpenter controller is installed (null if disabled). |
| <a name="output_karpenter_node_instance_profile_name"></a> [karpenter\_node\_instance\_profile\_name](#output\_karpenter\_node\_instance\_profile\_name) | Instance profile name used by the default EC2NodeClass (null if disabled). |
| <a name="output_karpenter_node_role_arn"></a> [karpenter\_node\_role\_arn](#output\_karpenter\_node\_role\_arn) | ARN of the IAM role attached to Karpenter-launched nodes (null if disabled). |
| <a name="output_kube_state_metrics_chart_version"></a> [kube\_state\_metrics\_chart\_version](#output\_kube\_state\_metrics\_chart\_version) | Installed version of the kube-state-metrics Helm chart (null if not installed). |
| <a name="output_lb_controller_chart_version"></a> [lb\_controller\_chart\_version](#output\_lb\_controller\_chart\_version) | Installed version of the aws-load-balancer-controller Helm chart (null if disabled). |
| <a name="output_lb_controller_namespace"></a> [lb\_controller\_namespace](#output\_lb\_controller\_namespace) | Namespace where the AWS Load Balancer Controller is installed (null if disabled). |
| <a name="output_log_retention_days"></a> [log\_retention\_days](#output\_log\_retention\_days) | How long logs stay queryable (null if logs are disabled). Enforced by Loki's compactor; the bucket lifecycle rule sweeps a week later as a backstop. |
| <a name="output_logs_cloudwatch_log_group"></a> [logs\_cloudwatch\_log\_group](#output\_logs\_cloudwatch\_log\_group) | CloudWatch Logs group Ravion's own log pipeline writes to (null unless cloudwatch is in logs\_providers). One stream per pod, named <namespace>/<pod>/<container>. Distinct from the add-on's /aws/containerinsights/<cluster>/application group. |
| <a name="output_logs_external_links"></a> [logs\_external\_links](#output\_logs\_external\_links) | One entry per ship-only log provider: { provider, name, href\_prefix }. href\_prefix ends exactly where a query value begins, so the service module appends its own encoded query and nothing else. Always a list, empty when there are none. |
| <a name="output_logs_opensearch_role_arn"></a> [logs\_opensearch\_role\_arn](#output\_logs\_opensearch\_role\_arn) | ARN of the role the collector signs OpenSearch requests with (null unless opensearch is in logs\_providers). Map it in the domain's access policy or its fine-grained role mapping - that half of the grant lives on the domain, which this module does not manage. |
| <a name="output_logs_providers"></a> [logs\_providers](#output\_logs\_providers) | Log destinations selected for this cluster, as given. Always a list - empty when logs are off, never null, because a service module reads null as 'these add-ons predate providers'. |
| <a name="output_logs_rendering_providers"></a> [logs\_rendering\_providers](#output\_logs\_rendering\_providers) | The selected log providers Ravion's Logs tab can read, in fallback order: loki, then cloudwatch. Empty when logs are off, or when only ship-only providers are selected — the tab then shows the 'Open in ...' actions alone. |
| <a name="output_loki_chart_version"></a> [loki\_chart\_version](#output\_loki\_chart\_version) | Installed version of the grafana/loki Helm chart (null if logs are disabled). |
| <a name="output_loki_endpoint"></a> [loki\_endpoint](#output\_loki\_endpoint) | In-cluster base URL of Loki (null if logs are disabled). Query through the Kubernetes API service proxy over the cluster's EKS-only SSM session. |
| <a name="output_loki_namespace"></a> [loki\_namespace](#output\_loki\_namespace) | Kubernetes namespace Loki and Alloy are installed into (null if logs are disabled). |
| <a name="output_loki_role_arn"></a> [loki\_role\_arn](#output\_loki\_role\_arn) | ARN of Loki's Pod Identity role, scoped to read, write, and delete on the log bucket alone (null if logs are disabled). Delete is what lets the compactor enforce retention. |
| <a name="output_loki_s3_bucket"></a> [loki\_s3\_bucket](#output\_loki\_s3\_bucket) | S3 bucket holding the log chunks and index (null if logs are disabled). Created by this module unless loki\_s3\_bucket\_name brought an existing one. |
| <a name="output_loki_s3_bucket_arn"></a> [loki\_s3\_bucket\_arn](#output\_loki\_s3\_bucket\_arn) | ARN of the log bucket (null if logs are disabled). What the Loki role is scoped to. |
| <a name="output_metrics_external_links"></a> [metrics\_external\_links](#output\_metrics\_external\_links) | One entry per ship-only metrics provider: { provider, name, href\_prefix }, on the same terms as logs\_external\_links. Always a list, empty when there are none. |
| <a name="output_metrics_namespace"></a> [metrics\_namespace](#output\_metrics\_namespace) | Kubernetes namespace the metrics components are installed into (null if metrics are disabled). |
| <a name="output_metrics_providers"></a> [metrics\_providers](#output\_metrics\_providers) | Metric destinations selected for this cluster, as given. Always a list - empty when metrics are off, never null. |
| <a name="output_metrics_rendering_providers"></a> [metrics\_rendering\_providers](#output\_metrics\_rendering\_providers) | The selected metric providers Ravion's Metrics tab can read, in fallback order: amp, then prometheus, then cloudwatch. Empty when metrics are off. |
| <a name="output_observability_credentials_secret_name"></a> [observability\_credentials\_secret\_name](#output\_observability\_credentials\_secret\_name) | Name of the first materialized vendor query Secret in the observability namespace (null when absent). Keys are username/password. External query support requires a credential-aware backend. |
| <a name="output_observability_namespace"></a> [observability\_namespace](#output\_observability\_namespace) | Kubernetes namespace the collectors, the log store, and the materialized vendor credentials are installed into. |
| <a name="output_observability_proxy_credentials"></a> [observability\_proxy\_credentials](#output\_observability\_proxy\_credentials) | Every proxy credential this module materialized: { endpointPrefix, secretName, kind }. observability\_credentials\_secret\_name is the first of them; this is the full mapping for a cluster that renders from more than one external store. |
| <a name="output_otel_collector_chart_version"></a> [otel\_collector\_chart\_version](#output\_otel\_collector\_chart\_version) | Installed version of the opentelemetry-collector Helm chart (null if metrics are disabled). |
| <a name="output_otel_logs_collector_role_arn"></a> [otel\_logs\_collector\_role\_arn](#output\_otel\_logs\_collector\_role\_arn) | ARN of the log collector's Pod Identity role (null unless a log provider authenticates with AWS credentials). Scoped to the Ravion log group and, for OpenSearch, to signing domain requests. |
| <a name="output_private_alb_arn"></a> [private\_alb\_arn](#output\_private\_alb\_arn) | ARN of the shared private ALB (null if disabled). |
| <a name="output_private_alb_arn_suffix"></a> [private\_alb\_arn\_suffix](#output\_private\_alb\_arn\_suffix) | ARN suffix of the shared private ALB, for CloudWatch metrics (null if disabled). |
| <a name="output_private_alb_dns_name"></a> [private\_alb\_dns\_name](#output\_private\_alb\_dns\_name) | DNS name of the shared private ALB (null if disabled). |
| <a name="output_private_alb_http_listener_arn"></a> [private\_alb\_http\_listener\_arn](#output\_private\_alb\_http\_listener\_arn) | ARN of the shared private ALB HTTP listener (null if disabled). |
| <a name="output_private_alb_https_listener_arn"></a> [private\_alb\_https\_listener\_arn](#output\_private\_alb\_https\_listener\_arn) | ARN of the shared private ALB HTTPS listener (null if disabled). |
| <a name="output_private_alb_security_group_id"></a> [private\_alb\_security\_group\_id](#output\_private\_alb\_security\_group\_id) | Security group ID of the shared private ALB (null if disabled). |
| <a name="output_private_alb_zone_id"></a> [private\_alb\_zone\_id](#output\_private\_alb\_zone\_id) | Route 53 zone ID of the shared private ALB (null if disabled). |
| <a name="output_private_nlb_arn"></a> [private\_nlb\_arn](#output\_private\_nlb\_arn) | ARN of the shared private NLB (null if disabled). |
| <a name="output_private_nlb_arn_suffix"></a> [private\_nlb\_arn\_suffix](#output\_private\_nlb\_arn\_suffix) | ARN suffix of the shared private NLB, for CloudWatch metrics (null if disabled). |
| <a name="output_private_nlb_dns_name"></a> [private\_nlb\_dns\_name](#output\_private\_nlb\_dns\_name) | DNS name of the shared private NLB (null if disabled). |
| <a name="output_private_nlb_security_group_id"></a> [private\_nlb\_security\_group\_id](#output\_private\_nlb\_security\_group\_id) | Security group ID of the shared private NLB (null if disabled). |
| <a name="output_private_nlb_zone_id"></a> [private\_nlb\_zone\_id](#output\_private\_nlb\_zone\_id) | Route 53 zone ID of the shared private NLB (null if disabled). |
| <a name="output_prometheus_chart_version"></a> [prometheus\_chart\_version](#output\_prometheus\_chart\_version) | Installed version of the prometheus Helm chart (null unless the module installed an in-cluster Prometheus). |
| <a name="output_prometheus_endpoint"></a> [prometheus\_endpoint](#output\_prometheus\_endpoint) | In-cluster Prometheus base URL (null unless prometheus is selected). Query through the Kubernetes API service proxy over SSM. |
| <a name="output_public_alb_arn"></a> [public\_alb\_arn](#output\_public\_alb\_arn) | ARN of the shared public ALB (null if disabled). |
| <a name="output_public_alb_arn_suffix"></a> [public\_alb\_arn\_suffix](#output\_public\_alb\_arn\_suffix) | ARN suffix of the shared public ALB, for CloudWatch metrics (null if disabled). |
| <a name="output_public_alb_dns_name"></a> [public\_alb\_dns\_name](#output\_public\_alb\_dns\_name) | DNS name of the shared public ALB (null if disabled). |
| <a name="output_public_alb_http_listener_arn"></a> [public\_alb\_http\_listener\_arn](#output\_public\_alb\_http\_listener\_arn) | ARN of the shared public ALB HTTP listener (null if disabled). |
| <a name="output_public_alb_https_listener_arn"></a> [public\_alb\_https\_listener\_arn](#output\_public\_alb\_https\_listener\_arn) | ARN of the shared public ALB HTTPS listener (null if disabled). |
| <a name="output_public_alb_security_group_id"></a> [public\_alb\_security\_group\_id](#output\_public\_alb\_security\_group\_id) | Security group ID of the shared public ALB (null if disabled). |
| <a name="output_public_alb_zone_id"></a> [public\_alb\_zone\_id](#output\_public\_alb\_zone\_id) | Route 53 zone ID of the shared public ALB (null if disabled). |
| <a name="output_public_nlb_arn"></a> [public\_nlb\_arn](#output\_public\_nlb\_arn) | ARN of the shared public NLB (null if disabled). |
| <a name="output_public_nlb_arn_suffix"></a> [public\_nlb\_arn\_suffix](#output\_public\_nlb\_arn\_suffix) | ARN suffix of the shared public NLB, for CloudWatch metrics (null if disabled). |
| <a name="output_public_nlb_dns_name"></a> [public\_nlb\_dns\_name](#output\_public\_nlb\_dns\_name) | DNS name of the shared public NLB (null if disabled). |
| <a name="output_public_nlb_security_group_id"></a> [public\_nlb\_security\_group\_id](#output\_public\_nlb\_security\_group\_id) | Security group ID of the shared public NLB (null if disabled). |
| <a name="output_public_nlb_zone_id"></a> [public\_nlb\_zone\_id](#output\_public\_nlb\_zone\_id) | Route 53 zone ID of the shared public NLB (null if disabled). |
| <a name="output_ravion_access_helm_inventory_namespaces"></a> [ravion\_access\_helm\_inventory\_namespaces](#output\_ravion\_access\_helm\_inventory\_namespaces) | Union of workload and observed namespaces where ravion:readers can get/list all Secrets for Helm inventory and drift. Empty grants no Secret access. |
<!-- END_TF_DOCS -->
