# GKE Service

Google Cloud side of a workload on a GKE cluster, the GKE counterpart of
`compute/eks_service`. The workload's Kubernetes objects come from the
`charts/rvn-gke-*` Helm charts, which Ravion deploys; this module owns what
lives outside the cluster:

- an optional Docker **Artifact Registry repository** with a keep-the-newest
  cleanup policy, for images Ravion builds;
- an optional **reserved address** (global external or regional internal) that
  the `rvn-gke-web` chart's GKE Gateway is pinned to, so the load balancer URL
  is known before the first deploy;
- a **Workload Identity** Google service account per stack, holding the
  project roles, which the release's Kubernetes service account acts as
  through `roles/iam.workloadIdentityUser` (the chart sets the
  `iam.gke.io/gcp-service-account` annotation from the email output). Roles
  are never granted to the Kubernetes principal itself: every cluster in a
  project shares one Workload Identity pool, so that principal, and the IAM
  member, would be shared with any other stack using the same namespace and
  release name;
- a destroy-time **`helm uninstall`** of the release through the cluster's
  IAM-authorized DNS endpoint, using the runner's Google access token.

Backs the `rvn-gke-web`, `rvn-gke-worker`, `rvn-gke-cron`, and `rvn-gke-chart`
module definitions.

## Usage

```hcl
module "web" {
  source = "git::https://github.com/ravionhq/modules.git//compute/gke_service?ref=rvn-gke-web@0.1.0"

  name       = "shop-prod-web"
  project_id = "my-project-123456"
  region     = "us-central1"

  release_name      = "shop-prod-web"
  release_namespace = "shop-prod"

  artifact_registry_repository_creation_enabled = true
  load_balancer_scheme                          = "external"
  hostnames                                     = ["shop.example.com"]
  gateway_certificate_map_name                  = "shop"
  workload_identity_project_roles               = ["roles/storage.objectViewer"]

  workload_release_cleanup_enabled = true
  cluster_name                     = "my-gke-cluster"
  dns_endpoint                     = "gke-0123456789abcdef-123456789012.us-central1.gke.goog"
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| google | >= 8.0 |

The runner identity needs `roles/artifactregistry.admin` (repository),
`roles/compute.networkAdmin` (addresses), `roles/iam.serviceAccountAdmin` and
`roles/resourcemanager.projectIamAdmin` (Workload Identity service account and
grants); Ravion's GCP setup gives the `ravion-runner` service account
`roles/editor`, which covers the first three. The release teardown also needs
`roles/container.admin`, which `compute/gke` does not grant because it covers
every cluster in the project: add it and `roles/resourcemanager.projectIamAdmin`
to `runner_sa_roles` in Ravion's GCP setup. An internal Gateway needs a proxy-only subnet in the region.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Workload name; names the repository and the address | `string` | n/a | yes |
| project_id | Google Cloud project of the cluster | `string` | n/a | yes |
| region | Region of the regional cluster | `string` | n/a | yes |
| labels | Labels applied to labelable resources | `map(string)` | `{}` | no |
| cluster_name | GKE cluster name (release teardown) | `string` | `null` | no |
| dns_endpoint | Cluster DNS endpoint (release teardown) | `string` | `null` | no |
| release_name | Helm release name | `string` | `null` | no |
| release_namespace | Helm release namespace | `string` | `null` | no |
| kubernetes_service_enabled | Chart renders a Service; enables service_* outputs | `bool` | `false` | no |
| container_port | Container and Service port | `number` | `8080` | no |
| load_balancer_scheme | `external`, `internal`, or `null` | `string` | `null` | no |
| subnetwork | Subnetwork for an internal address | `string` | `null` | no |
| hostnames | HTTPRoute hostnames | `list(string)` | `[]` | no |
| gateway_certificate_map_name | Certificate Manager map for HTTPS | `string` | `null` | no |
| gateway_pre_shared_certificate_names | Compute SSL certificates for HTTPS | `list(string)` | `[]` | no |
| artifact_registry_repository_creation_enabled | Create a Docker repository | `bool` | `false` | no |
| artifact_registry_repository_id | Repository ID; defaults to name | `string` | `null` | no |
| artifact_registry_immutable_tags_enabled | Reject moving tags | `bool` | `false` | no |
| artifact_registry_vulnerability_scanning_enabled | Scan pushed images | `bool` | `true` | no |
| artifact_registry_cleanup_policies_enabled | Keep only the newest images | `bool` | `true` | no |
| artifact_registry_max_image_count | Images kept | `number` | `100` | no |
| workload_identity_pool | Cluster Workload Identity pool | `string` | `null` | no |
| workload_identity_service_account_name | Kubernetes service account allowed to act as the Google service account; defaults to release_name | `string` | `null` | no |
| workload_identity_project_roles | Project roles granted to the workload's Google service account; requires cluster_name and release_namespace | `list(string)` | `[]` | no |
| workload_release_cleanup_enabled | Uninstall the release on destroy | `bool` | `false` | no |
| workload_release_helm_version | Helm downloaded when none is on PATH | `string` | `"v4.2.4"` | no |
| workload_release_uninstall_timeout | `helm uninstall --wait` timeout | `string` | `"10m"` | no |

## Outputs

| Name | Description |
|------|-------------|
| artifact_registry_repository_id | Repository ID (null if disabled) |
| artifact_registry_repository_url | Image path the chart deploys (null if disabled) |
| gateway_address_name | Reserved address name the Gateway uses |
| gateway_address | Reserved load balancer IP |
| load_balancer_url | URL through the Gateway |
| load_balancer_source_cidr_blocks | Ranges the load balancer reaches pods from |
| service_host | In-cluster Service DNS name |
| service_port | In-cluster Service port |
| service_url | In-cluster URL |
| workload_identity_service_account_email | Google service account the release acts as; the chart's `serviceAccount.gcpServiceAccount` |
| workload_identity_service_account_member | `serviceAccount:` IAM member of that account |
| project_id | Project of the resources |
| region | Region of the regional resources |
