# Temporal on EKS

Self-hosted [Temporal](https://temporal.io) on an existing EKS cluster, with its persistence and visibility stores on an Aurora PostgreSQL cluster.

The module installs two Helm releases into one namespace:

1. `<name>-resources`, a local chart ([`charts/temporal-resources`](charts/temporal-resources)) with everything around Temporal:
   - an `ExternalSecret` that copies the database password from Secrets Manager, so it never enters Helm values, release history or Terraform state
   - the RDS CA bundle, so the database connection verifies the server certificate
   - optionally, a private CA and certificates from cert-manager, a PriorityClass, a dedicated Karpenter NodePool, network policies and an OTLP metrics forwarder
2. `<name>`, the official [temporalio/helm-charts](https://github.com/temporalio/helm-charts) `temporal` chart, pinned to a version: the frontend, history, matching and worker services, the Web UI, the admin tools, a schema job that creates and migrates both databases, and a job that creates the Temporal namespaces.

Every service gets resource requests and limits, a `GOMEMLIMIT` at 90% of its memory limit, zone and node spread, a PodDisruptionBudget, and graceful shutdown drains.

## Usage

```hcl
module "temporal" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks/temporal?ref=v1.0.0"

  cluster_name           = "my-eks-cluster"
  region                 = "us-east-1"
  ravion_runner_role_arn = "arn:aws:iam::123456789012:role/my-eks-cluster-ravion-runner"

  database_cluster_identifier  = "my-temporal-db"
  database_password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-temporal-db-AbCdEf"

  num_history_shards = 512
  temporal_namespaces = {
    default = 7
    orders  = 30
  }

  history = { replicas = 3, memory_limit = "4Gi" }

  network_policy_frontend_client_namespaces = ["my-app"]
}
```

Clients in the cluster connect to the `frontend_address` output (`temporal-frontend.temporal.svc:7233` with the defaults).

## Prerequisites

- An EKS cluster with a storage driver and, for the default password source, the External Secrets Operator with a `ClusterSecretStore` for Secrets Manager (`ravion-aws` from the EKS Add-ons module). The store must allow this namespace, and the operator must be able to read the secret and decrypt it.
- An Aurora PostgreSQL cluster whose security group admits the EKS cluster's pods. The module checks the engine and refuses anything else.
- For `tls_enabled`, cert-manager. For `node_pool_creation_enabled`, Karpenter. For `metrics_service_monitor_enabled`, the Prometheus Operator CRDs.
- The AWS CLI on the machine running OpenTofu, for `aws eks get-token`.

## Notes

- **History shards are permanent.** `num_history_shards` cannot change after the first install without a new database.
- **Password rotation.** Temporal reads the password when a server starts. After the password changes, new database connections fail until the pods restart. Prefer a secret without automatic rotation, or restart the Temporal Deployments after each rotation.
- **Temporal namespaces** are created if missing. Retention of an existing namespace is not changed: use `temporal operator namespace update`.
- **Web UI** has no sign-in by default. Keep it on the ClusterIP Service or an internal load balancer, or add OIDC through `helm_values`.
- **Network policies** need a CNI that enforces them, such as the Amazon VPC CNI with network policy turned on. Without one they are inert.
- **TLS.** With `tls_enabled`, clients connect with TLS to `tls_server_name` and trust the `ca.crt` in the `tls_ca_secret_name` Secret. Copy only `ca.crt` out of it.
- Archival, Elasticsearch visibility, multi-cluster replication and authorization are not configured. Use `helm_values` for them.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |
| helm | >= 3.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the existing EKS cluster to install Temporal onto. | `string` | n/a | yes |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |
| ravion_runner_role_arn | IAM role assumed by `aws eks get-token` to authenticate to the Kubernetes API (ravion_runner_role_arn output of the compute/eks stack). When null, the identity running Terraform is used directly and must already have cluster access. | `string` | `null` | no |
| name | Helm release name. Every Kubernetes object the release creates is prefixed with it, such as &lt;name&gt;-frontend. | `string` | `"temporal"` | no |
| namespace | Kubernetes namespace for Temporal. A namespace of its own keeps the network policies and the CA secret away from other workloads. | `string` | `"temporal"` | no |
| namespace_creation_enabled | Create the Kubernetes namespace. Turn off when it is managed elsewhere. | `bool` | `true` | no |
| chart_version | Version of the temporalio/helm-charts `temporal` chart. Chart 1.8.0 or newer is required for the TLS settings this module writes. | `string` | `"1.8.0"` | no |
| server_image | Temporal server image, as repository:tag. The admin tools image (schema and namespace jobs) uses admin_tools_image. | `string` | `"temporalio/server:1.32.2"` | no |
| admin_tools_image | Temporal admin tools image, as repository:tag. Keep it on the same Temporal version as server_image: it runs the schema migrations. | `string` | `"temporalio/admin-tools:1.32.2"` | no |
| web_image | Temporal Web UI image, as repository:tag. | `string` | `"temporalio/ui:2.56.1"` | no |
| log_level | Temporal server log level. | `string` | `"info"` | no |
| num_history_shards | Number of history shards. Fixed for the life of the cluster: it cannot be changed after the first install without a new database. Each shard costs a little memory and database load even when idle, and the shard count caps how far history can scale out. 512 suits most teams; choose 2048 or more for very high throughput. | `number` | `512` | no |
| database_cluster_identifier | Identifier of the Aurora PostgreSQL cluster Temporal uses. The cluster must accept connections from the EKS cluster's pods. | `string` | n/a | yes |
| database_username | Database user Temporal connects as. When null, the cluster's master username. | `string` | `null` | no |
| database_password_source | Where the database password comes from. `external_secrets` copies it from Secrets Manager with the External Secrets Operator; `kubernetes_secret` reads an existing Kubernetes Secret in the namespace. | `string` | `"external_secrets"` | no |
| database_password_secret_arn | ARN of the Secrets Manager secret holding the database credentials as JSON, such as the Aurora cluster's master user secret. Required when database_password_source is external_secrets. | `string` | `null` | no |
| database_password_secret_property | JSON key in the Secrets Manager secret that holds the password. | `string` | `"password"` | no |
| database_password_secret_store_name | External Secrets ClusterSecretStore that reads Secrets Manager. It must admit this namespace and be allowed to read the secret (and decrypt it, for a customer managed KMS key). | `string` | `"ravion-aws"` | no |
| database_password_refresh_interval | How often the External Secrets Operator re-reads the password. | `string` | `"1h"` | no |
| database_password_kubernetes_secret_name | Kubernetes Secret holding the password under the key `password`. With external_secrets it is created under this name; when null, &lt;name&gt;-db. | `string` | `null` | no |
| database_name | Database holding Temporal's persistence (workflow state and history). | `string` | `"temporal"` | no |
| visibility_database_name | Database holding Temporal's visibility records (workflow search and listing). | `string` | `"temporal_visibility"` | no |
| database_schema_management_enabled | Create both databases if missing and run Temporal's schema migrations on every deploy. Turn off only when a database administrator manages the schema. | `bool` | `true` | no |
| database_tls_enabled | Connect to the database over TLS and verify its certificate against the RDS CA bundle. | `bool` | `true` | no |
| database_max_connections | Maximum connections each Temporal server pod opens to the persistence database. Multiply by the number of server pods to size the database's max_connections. | `number` | `20` | no |
| visibility_database_max_connections | Maximum connections each Temporal server pod opens to the visibility database. | `number` | `10` | no |
| frontend | Frontend service: the gRPC API SDK clients, the Web UI and the CLI call. | `object` | `{}` | no |
| history | History service: owns the history shards and does most of the work. Scale it first, and give it memory: each pod caches the workflows of the shards it owns. | `object` | `{}` | no |
| matching | Matching service: hosts the task queues workers poll. | `object` | `{}` | no |
| worker | Internal worker service: runs Temporal's own system workflows, such as scheduled actions and batch operations. | `object` | `{}` | no |
| temporal_namespaces | Temporal namespaces created on install, keyed by name, each with how many days closed workflows are kept. Namespaces that already exist are left as they are: change retention with `temporal operator namespace update`. | `map(number)` | `{ default = 7 }` | no |
| topology_spread | Spread each service's replicas across zones and nodes. `preferred` spreads when it can; `required` refuses to schedule a replica that would break the spread, which needs nodes in every zone (Karpenter adds them); `off` leaves placement to the scheduler. | `string` | `"preferred"` | no |
| pod_disruption_budgets_enabled | Let voluntary disruptions, such as node drains, take at most one replica of each service at a time. | `bool` | `true` | no |
| priority_class_creation_enabled | Create a PriorityClass ranking Temporal above ordinary workloads, so the scheduler preempts and the kubelet evicts other pods first. | `bool` | `false` | no |
| priority_class_name | PriorityClass for every Temporal pod. With priority_class_creation_enabled it is created under this name (when null, &lt;name&gt;-critical); otherwise it must already exist, or be null for none. | `string` | `null` | no |
| priority_class_value | Priority of the created PriorityClass. Keep it below the system-cluster-critical (2000000000) and system-node-critical classes. | `number` | `1000000` | no |
| node_pool_creation_enabled | Create a dedicated, tainted Karpenter NodePool and run Temporal on it alone, so other workloads cannot starve it and node consolidation moves its pods one node at a time. Requires Karpenter, such as from the EKS Add-ons module. | `bool` | `false` | no |
| node_pool | Settings for the dedicated NodePool. Spot capacity is allowed but not recommended: a reclaim moves history shards mid-flight. | `object` | `{}` | no |
| network_policy_enabled | Close the Temporal pods' internal ports to everything outside the release. Enforcement needs a CNI that implements NetworkPolicy, such as the Amazon VPC CNI with network policy turned on; without one the policies are inert. | `bool` | `true` | no |
| network_policy_frontend_client_namespaces | Namespaces whose pods may call the frontend (gRPC 7233, HTTP 7243). Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| network_policy_web_client_namespaces | Namespaces whose pods may reach the Web UI, such as an ingress controller's. Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| network_policy_web_client_cidrs | CIDR blocks that may reach the Web UI pods directly. The VPC CIDR is added automatically when the Web UI ingress is enabled. | `list(string)` | `[]` | no |
| network_policy_metrics_namespaces | Namespaces whose pods may scrape the servers' metrics port (9090). Empty allows every namespace in the cluster. | `list(string)` | `[]` | no |
| tls_enabled | Encrypt Temporal's traffic with certificates from a private CA that cert-manager creates in the namespace: mutual TLS between Temporal's services, and TLS on the frontend. Requires cert-manager, such as from the EKS Add-ons module. SDK clients must then connect with TLS and trust the CA in the frontend certificate secret's ca.crt. | `bool` | `false` | no |
| tls_frontend_client_auth_required | Require SDK clients to present a certificate from the private CA (mutual TLS) on the frontend. | `bool` | `false` | no |
| web_enabled | Run the Temporal Web UI. It has no sign-in of its own: anyone who can reach it can read and act on every namespace. | `bool` | `true` | no |
| web | Web UI replicas and resources. | `object` | `{}` | no |
| web_ingress_enabled | Expose the Web UI through an Ingress. With the default `alb` class it is an internal Application Load Balancer, reachable only from inside the VPC and networks connected to it. | `bool` | `false` | no |
| web_ingress_class_name | IngressClass for the Web UI. `alb` is the AWS Load Balancer Controller's. | `string` | `"alb"` | no |
| web_ingress_host | Host name the Web UI Ingress answers on. When null, every host. | `string` | `null` | no |
| web_ingress_certificate_arn | ACM certificate for HTTPS on the internal ALB (alb class only). When null, the ALB listens on HTTP 80. | `string` | `null` | no |
| web_ingress_annotations | Annotations merged over the module's Ingress annotations, for example to join a shared ALB with alb.ingress.kubernetes.io/group.name. | `map(string)` | `{}` | no |
| metrics_prometheus_annotations_enabled | Annotate the server pods with prometheus.io/scrape, for scrapers that discover pods by annotation. | `bool` | `true` | no |
| metrics_service_monitor_enabled | Create Prometheus Operator ServiceMonitors for the servers. Requires the monitoring.coreos.com CRDs. | `bool` | `false` | no |
| metrics_otlp_endpoint | OTLP gRPC endpoint (host:port or http://host:port) to push the servers' metrics to, such as the EKS Add-ons module's otlp_grpc_endpoint output. A small forwarder in the namespace scrapes the servers and pushes the samples. When null, no forwarder runs. | `string` | `null` | no |
| metrics_otlp_metric_families | Metric families the forwarder keeps, as regular expressions without the _bucket/_sum/_count/_total suffixes. Empty keeps everything, which can be many series on a busy cluster. | `list(string)` | `(curated list)` | no |
| metrics_otlp_collector_image | OpenTelemetry Collector image for the metrics forwarder. It must include the prometheus receiver and the otlp_grpc exporter. | `string` | `"otel/opentelemetry-collector-contrib:0.161.0"` | no |
| helm_values | Extra YAML values documents for the upstream Temporal chart, applied after the module's own values, for settings this module has no input for (Web UI sign-in, authorization, dynamic config). | `list(string)` | `[]` | no |
| helm_timeout_seconds | How long an install or upgrade waits for the schema job and every Temporal pod to be ready. | `number` | `900` | no |
| tags | A map of tags applied, as provider default tags, to any AWS resource the module creates. | `map(string)` | `{}` | no |

The service objects (`frontend`, `history`, `matching`, `worker`, `web`) take `replicas`, `cpu_request`, `memory_request` and `memory_limit`; see `variables.tf` for their defaults. `node_pool` takes `ec2_node_class_name`, `capacity_types`, `instance_categories`, `architectures`, `cpu_limit` and `consolidate_after`.

## Outputs

| Name | Description |
|------|-------------|
| release_name | Name of the Temporal Helm release. Every Service it creates is prefixed with it. |
| namespace | Kubernetes namespace Temporal runs in. |
| chart_version | Version of the upstream Temporal chart installed. |
| frontend_address | In-cluster gRPC address of the Temporal frontend, host:port, for SDK clients and the CLI (TEMPORAL_ADDRESS). |
| frontend_host | In-cluster host name of the Temporal frontend Service. |
| frontend_port | gRPC port of the Temporal frontend. |
| frontend_http_address | In-cluster address of the frontend's HTTP API, host:port. |
| temporal_namespaces | Temporal namespaces the module creates on install. |
| num_history_shards | Number of history shards the cluster was configured with. |
| web_address | In-cluster URL of the Web UI (null when the Web UI is off). |
| web_url | URL of the Web UI through its Ingress (null unless the Ingress is enabled with a host). |
| tls_enabled | Whether the frontend serves TLS. SDK clients must then connect with TLS. |
| tls_server_name | Name SDK clients verify the frontend certificate against (null when TLS is off). |
| tls_ca_secret_name | Kubernetes Secret in the namespace whose ca.crt is the CA SDK clients trust for the frontend (null when TLS is off). Copy only ca.crt to clients: the Secret also holds the frontend's private key. |
| database_endpoint | Endpoint of the Aurora cluster Temporal uses. |
| database_secret_name | Kubernetes Secret holding the database password. |
| priority_class_name | PriorityClass the Temporal pods run with (null when none). |
| node_pool_name | Dedicated Karpenter NodePool Temporal runs on (null when not created). |
