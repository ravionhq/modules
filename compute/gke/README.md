# GKE Cluster

A regional Google Kubernetes Engine (GKE) Standard cluster with private nodes, Workload Identity, Dataplane V2, a dedicated least-privilege node service account, an autoscaled system node pool plus optional On-demand or Spot pools, and node auto-provisioning. The Ravion runner service account is granted Kubernetes Engine Admin so pipelines, such as the [GKE Add-ons](addons) module, can manage Kubernetes objects.

The cluster starts with no default node pool. Every pool, the system pool included, is a separate `google_container_node_pool` created with a name prefix and `create_before_destroy`, so a change GKE can only make by recreating a pool brings up its replacement first. Node counts are totals across zones, and the cluster autoscaler owns the running count.

The control plane's DNS-based endpoint accepts IAM-authorized requests from outside the VPC by default, so Terraform runners reach the Kubernetes API without a network path into the VPC. The IP-based endpoint is private unless `ip_endpoint_public_access_enabled` is set.

Module definition: `rvn-gke-cluster` ([`rvn-gke-cluster-definition.yml`](rvn-gke-cluster-definition.yml)).

## Usage

```hcl
module "gke" {
  source = "git::https://github.com/ravionhq/modules.git//compute/gke?ref=rvn-gke-cluster@0.1.0"

  name       = "acme-production"
  project_id = "acme-production-123456"
  region     = "us-central1"

  node_pools = {
    batch = {
      capacity_type = "SPOT"
      machine_type  = "n2-standard-8"
      min_nodes     = 0
      max_nodes     = 20
      taints        = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
    }
  }

  labels = { team = "platform" }
}
```

## Permissions

The identity running Terraform needs to create GKE clusters and service accounts and to change project IAM policy: `roles/editor` plus `roles/resourcemanager.projectIamAdmin`. Ravion's GCP setup gives the `ravion-runner` service account `roles/editor` by default; add `roles/resourcemanager.projectIamAdmin` through its `runner_sa_roles` variable. Without IAM policy access, set `node_service_account_creation_enabled = false` with an existing `node_service_account_email`, set `ravion_runner_cluster_admin_enabled = false`, and leave `access_members` empty.

Nodes have no external IPs, so the subnetwork needs Cloud NAT for nodes to pull public images.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.12.0 |
| google | >= 8.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the GKE cluster. Also prefixes the node service account. | `string` | n/a | yes |
| project_id | ID of the Google Cloud project the cluster is created in. | `string` | n/a | yes |
| region | Region of the regional cluster, such as `us-central1`. | `string` | n/a | yes |
| node_locations | Zones in the region that run nodes. Null uses GKE's default zones. | `list(string)` | `null` | no |
| labels | Labels for the cluster and node VMs and disks, normalized to valid GCP labels. | `map(string)` | `{}` | no |
| network | Name or self link of the VPC network. | `string` | `"default"` | no |
| subnetwork | Name or self link of the regional subnetwork for nodes. | `string` | `"default"` | no |
| pods_secondary_range_name | Existing secondary range for pod IPs. Null lets GKE create one. | `string` | `null` | no |
| services_secondary_range_name | Existing secondary range for Service IPs. Null lets GKE create one. | `string` | `null` | no |
| pods_ipv4_cidr_block | CIDR or netmask for the pod range GKE creates. | `string` | `null` | no |
| services_ipv4_cidr_block | CIDR or netmask for the Service range GKE creates. | `string` | `null` | no |
| dataplane_v2_enabled | Use Dataplane V2, which enforces NetworkPolicy. Changing it replaces the cluster. | `bool` | `true` | no |
| gateway_api_enabled | Install the standard Gateway API CRDs and GKE's Gateway controller. | `bool` | `true` | no |
| release_channel | `RAPID`, `REGULAR`, `STABLE`, or `EXTENDED`. | `string` | `"REGULAR"` | no |
| kubernetes_version | Minimum control plane version. Null uses the channel default. | `string` | `null` | no |
| deletion_protection_enabled | Fail plans that would delete or replace the cluster. | `bool` | `true` | no |
| secrets_kms_key_name | Cloud KMS key for application-layer Secrets encryption. | `string` | `null` | no |
| node_service_account_creation_enabled | Create a dedicated node service account. | `bool` | `true` | no |
| node_service_account_email | Existing node service account when creation is off. | `string` | `null` | no |
| system_node_pool | System pool: `capacity_type`, `machine_type`, `min_nodes`, `max_nodes`, `disk_size_gb`, `disk_type`, `taints`. | `object` | 2-3 On-demand `e2-standard-2` | no |
| node_pools | Additional autoscaled pools keyed by a 1-13 character name prefix. | `map(object)` | `{}` | no |
| node_auto_provisioning_enabled | Let GKE create node pools for pending pods. | `bool` | `true` | no |
| node_auto_provisioning_cpu_limit | Cluster-wide vCPU limit with auto-provisioning. | `number` | `100` | no |
| node_auto_provisioning_memory_limit_gb | Cluster-wide memory limit in GB with auto-provisioning. | `number` | `400` | no |
| autoscaling_profile | `BALANCED` or `OPTIMIZE_UTILIZATION`. | `string` | `"BALANCED"` | no |
| dns_endpoint_enabled | Allow IAM-authorized requests to the DNS endpoint from outside the VPC. | `bool` | `true` | no |
| ip_endpoint_public_access_enabled | Expose the public IP endpoint. | `bool` | `false` | no |
| master_authorized_cidr_blocks | IPv4 CIDR blocks allowed to reach the IP endpoints. | `list(string)` | `[]` | no |
| ravion_runner_cluster_admin_enabled | Grant the Ravion runner service account `roles/container.admin`. | `bool` | `true` | no |
| ravion_runner_service_account_email | Ravion runner service account. Null uses `ravion-runner@<project_id>.iam.gserviceaccount.com`. | `string` | `null` | no |
| access_members | IAM principals granted a GKE role on the project: `member` and `role`. | `map(object)` | `{}` | no |
| logging_components | Components whose logs go to Cloud Logging. | `list(string)` | `["SYSTEM_COMPONENTS", "WORKLOADS"]` | no |
| managed_prometheus_enabled | Collect metrics with Managed Service for Prometheus. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | Name of the GKE cluster. |
| cluster_id | Fully qualified ID of the cluster. |
| project_id | Project the cluster runs in. |
| region | Region of the regional cluster. |
| kubernetes_version | Current control plane version. |
| endpoint | IP address of the control plane endpoint. |
| dns_endpoint | DNS-based control plane endpoint. |
| dns_endpoint_external_access_enabled | Whether the DNS endpoint accepts requests from outside the VPC. |
| cluster_ca_certificate | Base64-encoded CA certificate of the IP-based endpoint. |
| workload_identity_pool | Workload Identity pool of the cluster. |
| network | VPC network the cluster runs in. |
| subnetwork | Subnetwork the nodes run in. |
| node_service_account_email | Service account the nodes run as. |
| node_pool_names | Generated node pool names, keyed by pool key. |
| system_node_labels | Kubernetes labels on the system node pool. |
| system_node_min_nodes | Minimum node count of the system pool. |
| ravion_runner_service_account_email | Service account granted `roles/container.admin`, or null. |
