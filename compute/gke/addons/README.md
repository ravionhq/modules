# GKE Add-ons

Selectable add-ons for an existing GKE cluster, each toggled independently:

| Add-on | Toggle | Default | What it creates |
|---|---|---|---|
| **KEDA** | `keda_enabled` | `false` | Operator, external metrics API server, admission webhooks and CRDs from the official KEDA Helm chart |
| **cert-manager** | `cert_manager_enabled` | `false` | Controller, webhook, CA injector and CRDs from the official Jetstack Helm chart; CRDs are kept on uninstall |
| **External Secrets Operator** | `eso_enabled` | `false` | The `external-secrets` Helm chart, `roles/secretmanager.secretAccessor` for its Kubernetes service account through Workload Identity (project-wide, or on the secrets in `eso_secret_ids`), the Secret Manager API, and a `ravion-gcp` ClusterSecretStore limited to `eso_allowed_namespaces` (local `charts/external-secrets-resources`) |

GKE itself provides the rest of what the EKS Add-ons module installs: Gateway API and Ingress load balancing, the Persistent Disk CSI driver, the cluster autoscaler and node auto-provisioning, Cloud Logging, and Managed Prometheus. Configure those on the [`compute/gke`](..) cluster.

Module definition: `rvn-gke-addons` ([`rvn-gke-addons-definition.yml`](rvn-gke-addons-definition.yml)).

> **Connectivity:** the Helm provider authenticates with the access token of the identity running Terraform. On a Ravion runner that is the `ravion-runner` service account, which `compute/gke` grants `roles/container.admin`. With `use_dns_endpoint` (the default) it reaches the cluster's IAM-authorized DNS endpoint, so the runner needs no network path into the VPC. With `use_dns_endpoint = false` it uses the IP endpoint and cluster CA, and the runner must be able to reach it.

## Placement

With `addon_placement_enabled` (the default) every add-on pod requires a node that is neither Spot nor preemptible (`cloud.google.com/gke-spot` and `cloud.google.com/gke-preemptible` not `true`), prefers nodes labelled with `system_node_labels` (`role=system`, the label `compute/gke` gives its system pool), and tolerates `CriticalAddonsOnly`. The placement is its own Helm values document ahead of each release's caller values.

## Usage

```hcl
module "gke_addons" {
  source = "git::https://github.com/ravionhq/modules.git//compute/gke/addons?ref=rvn-gke-addons@0.1.0"

  cluster_name = module.gke.cluster_name
  project_id   = module.gke.project_id
  region       = module.gke.region

  cert_manager_enabled = true
  keda_enabled         = true

  eso_enabled            = true
  eso_allowed_namespaces = ["web", "worker"]
}
```

With the External Secrets Operator on, the identity running Terraform also needs to change IAM policy: `roles/resourcemanager.projectIamAdmin`, or `roles/secretmanager.admin` when `eso_secret_ids` lists secrets.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| google | >= 8.0 |
| helm | >= 3.1 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the existing GKE cluster. | `string` | n/a | yes |
| project_id | Project the cluster runs in. | `string` | n/a | yes |
| region | Region of the regional cluster. | `string` | n/a | yes |
| use_dns_endpoint | Reach the Kubernetes API through the DNS-based endpoint. | `bool` | `true` | no |
| addon_placement_enabled | Keep add-ons off Spot nodes, prefer the system pool, tolerate CriticalAddonsOnly. | `bool` | `true` | no |
| system_node_labels | Labels of the system node pool, which add-ons prefer. | `map(string)` | `{ role = "system" }` | no |
| cert_manager_enabled | Install cert-manager. | `bool` | `false` | no |
| cert_manager_namespace | Namespace for cert-manager. | `string` | `"cert-manager"` | no |
| cert_manager_chart_version | Version of the jetstack/cert-manager chart. | `string` | `"v1.21.2"` | no |
| cert_manager_helm_values | Extra Helm values documents for cert-manager. | `list(string)` | `[]` | no |
| keda_enabled | Install KEDA. | `bool` | `false` | no |
| keda_namespace | Namespace for KEDA. | `string` | `"keda"` | no |
| keda_chart_version | Version of the kedacore/keda chart. | `string` | `"2.20.2"` | no |
| keda_helm_values | Extra Helm values documents for KEDA. | `list(string)` | `[]` | no |
| eso_enabled | Install the External Secrets Operator with Secret Manager access. | `bool` | `false` | no |
| eso_namespace | Namespace for the operator. | `string` | `"external-secrets"` | no |
| eso_service_account | Kubernetes service account of the controller. | `string` | `"external-secrets"` | no |
| eso_chart_version | Version of the external-secrets chart. | `string` | `"2.11.0"` | no |
| eso_secret_ids | Secrets the controller may read. Empty grants every secret in the project. | `list(string)` | `[]` | no |
| eso_allowed_namespaces | Namespaces that may use the cluster secret store. Required when the store is created. | `list(string)` | `[]` | no |
| eso_cluster_secret_store_creation_enabled | Create the shared ClusterSecretStore. | `bool` | `true` | no |
| eso_cluster_secret_store_name | Name of the shared store. | `string` | `"ravion-gcp"` | no |
| eso_helm_values | Extra Helm values documents for the operator. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | Name of the GKE cluster the add-ons are installed onto. |
| cert_manager_namespace | Namespace of cert-manager, or null. |
| keda_namespace | Namespace of KEDA, or null. |
| eso_namespace | Namespace of the External Secrets Operator, or null. |
| eso_cluster_secret_store_name | Name of the Secret Manager ClusterSecretStore, or null. |
| eso_principal | Workload Identity principal of the External Secrets controller, or null. |
