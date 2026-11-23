# GCP VPC Network

Creates a custom-mode Google Cloud VPC network with one regional subnetwork per region (with GKE pods and services secondary ranges), Cloud Router and Cloud NAT, Private Google Access, Private Service Access for Cloud SQL / AlloyDB / Memorystore / Filestore, optional proxy-only subnetworks, firewall rules, VPC Network Peering, and VPC Flow Logs.

This is the Google Cloud counterpart of `networking/vpc` and backs the `rvn-gcp-network` module definition.

## Public and private subnets

Google Cloud has no public/private subnet split. A VPC network is global, a subnetwork is regional and spans every zone, and a resource is public only when it has an external IP address. This module therefore creates **one subnetwork per region** instead of public/private pairs per availability zone:

| AWS `networking/vpc` | This module |
| --- | --- |
| `private_subnet_ids` (one per AZ) | `subnetwork_ids[region]` / `subnetwork_id` (one per region, spans all zones) |
| `public_subnet_ids` (for load balancers, NAT) | none. External load balancers use Google's edge; regional Envoy load balancers use `proxy_only_subnetwork_ids` |
| NAT gateway in a public subnet | Cloud NAT on a Cloud Router per region (managed, highly available) |
| `vpc_id` | `network_id` / `network_self_link` |
| S3/DynamoDB gateway endpoints, interface endpoints | Private Google Access (`private_google_access_enabled`) |
| — | Private Service Access range + connection for managed databases |

## Usage

```hcl
module "network" {
  source = "git::https://github.com/ravionhq/modules.git//networking/gcp_vpc?ref=v1.0.0"

  name       = "acme-prod"
  project_id = "acme-prod-123"
  region     = "us-central1"

  additional_regions = ["europe-west1"]

  firewall_rules = {
    iap-ssh = {
      source_ranges = ["35.235.240.0/20"]
      ports         = ["22"]
      target_tags   = ["ssh"]
    }
  }

  labels = {
    environment = "production"
  }
}

# Cloud SQL with a private IP in this network
resource "google_sql_database_instance" "db" {
  # ...
  settings {
    ip_configuration {
      ipv4_enabled       = false
      private_network    = module.network.network_id
      allocated_ip_range = module.network.private_service_access_range_name
    }
  }
  depends_on = [module.network]
}
```

## Address plan

`network_cidr` (default `10.0.0.0/12`) is split into 8 equal blocks. Block N belongs to the Nth region (`region` first, then `additional_regions` in order); the last block holds the Private Service Access range. Within a region block, the first half is the GKE pods range and the second half holds the subnetwork, GKE services, and proxy-only ranges.

| Range | `us-central1` (primary) | 2nd region |
| --- | --- | --- |
| Pods (secondary `pods`) | `10.0.0.0/16` | `10.2.0.0/16` |
| Subnetwork | `10.1.0.0/20` | `10.3.0.0/20` |
| Services (secondary `services`) | `10.1.16.0/20` | `10.3.16.0/20` |
| Proxy-only | `10.1.32.0/23` | `10.3.32.0/23` |
| Private Service Access | `10.14.0.0/16` | (shared) |

Add regions at the end of `additional_regions`; removing or reordering one changes the ranges of the regions after it.

## Requirements

| Name | Version |
| --- | --- |
| opentofu/terraform | >= 1.10.0 |
| google | >= 8.1 |

Credentials come from Application Default Credentials (for example a Ravion runner VM's service account). The module enables `compute.googleapis.com` and, with Private Service Access, `servicenetworking.googleapis.com`, and leaves them enabled on destroy.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| name | Network name and resource name prefix (1-30 characters) | `string` | n/a | yes |
| project_id | Google Cloud project ID | `string` | n/a | yes |
| region | Primary region | `string` | n/a | yes |
| labels | Labels for resources that support them (sanitized to GCP label rules) | `map(string)` | `{}` | no |
| network_cidr | Range all subnetwork, secondary, proxy-only, and PSA ranges are carved from (/8 to /14) | `string` | `"10.0.0.0/12"` | no |
| additional_regions | Up to 5 more regions with their own subnetwork, router, and NAT | `list(string)` | `[]` | no |
| routing_mode | `REGIONAL` or `GLOBAL` dynamic routing | `string` | `"REGIONAL"` | no |
| subnetwork_secondary_ranges_enabled | Add GKE `pods` and `services` secondary ranges | `bool` | `true` | no |
| private_google_access_enabled | Private Google Access on every subnetwork | `bool` | `true` | no |
| proxy_only_subnetwork_creation_enabled | Create a proxy-only subnetwork per region | `bool` | `false` | no |
| nat_enabled | Create a Cloud Router and Cloud NAT per region | `bool` | `true` | no |
| nat_static_ip_count | Static NAT addresses reserved per region; 0 for automatic allocation | `number` | `1` | no |
| nat_ip_self_links | Existing NAT addresses by region; overrides `nat_static_ip_count` for that region | `map(list(string))` | `{}` | no |
| nat_min_ports_per_vm | Minimum NAT ports per VM | `number` | `64` | no |
| nat_logging_enabled | Cloud NAT logging | `bool` | `true` | no |
| nat_logging_filter | `ERRORS_ONLY`, `TRANSLATIONS_ONLY`, or `ALL` | `string` | `"ERRORS_ONLY"` | no |
| private_service_access_enabled | Reserve a PSA range and create the service networking connection | `bool` | `true` | no |
| private_service_access_deletion_policy | `DELETE`, `REMOVE_PEERING`, or `ABANDON` | `string` | `"DELETE"` | no |
| flow_logs_enabled | VPC Flow Logs on every subnetwork | `bool` | `true` | no |
| flow_logs_aggregation_interval | Flow log aggregation interval | `string` | `"INTERVAL_5_SEC"` | no |
| flow_logs_sampling | Fraction of flows logged (0, 1] | `number` | `0.5` | no |
| firewall_internal_ingress_enabled | Allow all ingress from this network's own ranges | `bool` | `false` | no |
| firewall_rules | Extra firewall rules keyed by short name | `map(object)` | `{}` | no |
| network_peerings | VPC Network Peerings keyed by short name | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| project_id | Project ID |
| region | Primary region |
| regions | Every region with a subnetwork, primary first |
| network_id | Network ID (`projects/<p>/global/networks/<name>`) |
| network_name | Network name |
| network_self_link | Network self link |
| network_cidr | Network range |
| subnetwork_id / subnetwork_name / subnetwork_self_link / subnetwork_cidr | Primary region's subnetwork |
| subnetwork_ids / subnetwork_names / subnetwork_self_links / subnetwork_cidrs | Maps of region to subnetwork |
| pods_secondary_range_name / services_secondary_range_name | GKE secondary range names (null when disabled) |
| pods_secondary_range_cidrs / services_secondary_range_cidrs | Maps of region to GKE secondary ranges |
| proxy_only_subnetwork_ids / proxy_only_subnetwork_cidrs | Maps of region to proxy-only subnetwork |
| nat_router_names / nat_names | Maps of region to Cloud Router / Cloud NAT name |
| nat_ip_addresses | Map of region to NAT addresses reserved by this module |
| nat_ip_self_links | Map of region to the address self links Cloud NAT uses |
| private_service_access_range_name | PSA range name, for `allocated_ip_range` |
| private_service_access_cidr | PSA range |
| private_service_access_connection_id | Service networking connection ID |
| firewall_rule_names | Map of `firewall_rules` keys to rule names |
| network_peering_states | Map of `network_peerings` keys to peering state |

## Testing

```bash
tofu init -backend=false
tofu test
```
