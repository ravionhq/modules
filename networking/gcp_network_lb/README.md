# GCP Network Load Balancer

Creates a regional passthrough Network Load Balancer on Google Cloud: an external one with a reserved static IP address, or an internal one with an IP address from a subnetwork. It includes a regional health check, a regional backend service for your instance groups or GCE_VM_IP network endpoint groups, a forwarding rule for TCP, UDP, or all IP protocols, and the firewall rules that let health checkers and clients reach the backends.

This is the Google Cloud counterpart of `networking/nlb`. It is Terraform-only and has no module definition: it does nothing until a TCP/UDP workload module (a managed instance group or GKE service) adds backends.

## Differences from the AWS NLB module

| AWS `networking/nlb` | This module |
| --- | --- |
| Listeners and target groups added by service modules | One forwarding rule (up to 5 ports or port ranges, or all ports) and one backend service per load balancer |
| Elastic IPs per AZ (`elastic_ip_allocation_ids`) | One regional static IP address (`ip_address_creation_enabled` or `ip_address`) |
| Security group on the NLB | No security group. Passthrough keeps the client IP, so the backends' firewall rules allow clients and Google health checkers |
| Cross-zone load balancing toggle | Always regional across zones |
| S3 access logs | Connection logs in Cloud Logging (`logging_enabled`) |
| TLS listeners | Not supported by passthrough load balancers. Use a proxy Network Load Balancer or terminate TLS on the backends |

## Usage

```hcl
module "game_lb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/gcp_network_lb?ref=v1.0.0"

  name       = "game"
  project_id = "acme-prod-123"
  region     = "us-central1"
  network    = module.network.network_id

  protocol = "UDP"
  ports    = ["7777"]
  backends = [{ group = google_compute_region_instance_group_manager.game.instance_group }]

  # UDP cannot be health checked directly
  health_check = {
    protocol = "HTTP"
    port     = 8080
    request_path = "/healthz"
  }

  target_tags = ["game"]
}

# Internal load balancer on all ports and protocols
module "internal_lb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/gcp_network_lb?ref=v1.0.0"

  name                           = "internal"
  project_id                     = "acme-prod-123"
  region                         = "us-central1"
  internal_load_balancer_enabled = true
  network                        = module.network.network_id
  subnetwork                     = module.network.subnetwork_id
  protocol                       = "L3_DEFAULT"
  ingress_source_ranges          = [module.network.network_cidr]
  backends                       = [{ group = "projects/acme-prod-123/regions/us-central1/instanceGroups/app" }]
  health_check                   = { port = 8080 }
}
```

## Requirements

| Name | Version |
| --- | --- |
| opentofu/terraform | >= 1.10.0 |
| google | >= 8.1 |

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| name | Name prefix (1-42 characters) | `string` | n/a | yes |
| project_id | Google Cloud project ID | `string` | n/a | yes |
| region | Region of the load balancer and backends | `string` | n/a | yes |
| labels | Labels for resources that support them | `map(string)` | `{}` | no |
| internal_load_balancer_enabled | Internal instead of external | `bool` | `false` | no |
| network | Network self link or ID of the backends | `string` | n/a | yes |
| subnetwork | Subnetwork self link or ID for an internal load balancer | `string` | `null` | for internal |
| protocol | `TCP`, `UDP`, or `L3_DEFAULT` | `string` | `"TCP"` | no |
| ports | Up to 5 ports or ranges; empty for all ports | `list(string)` | `[]` | no |
| ip_address_creation_enabled | Reserve a static IP address | `bool` | `true` | no |
| ip_address | Existing address when not reserving one | `string` | `null` | no |
| network_tier | `PREMIUM` or `STANDARD` (external only) | `string` | `"PREMIUM"` | no |
| global_access_enabled | Clients in any region can reach an internal load balancer | `bool` | `false` | no |
| backends | Instance groups or GCE_VM_IP NEGs, with optional `failover` (internal only) | `list(object)` | `[]` | no |
| session_affinity | `NONE`, `CLIENT_IP`, `CLIENT_IP_PROTO`, or `CLIENT_IP_PORT_PROTO` | `string` | `"NONE"` | no |
| connection_draining_timeout_seconds | Draining timeout | `number` | `300` | no |
| health_check | `protocol` (TCP/HTTP/HTTPS), `port`, `request_path`, intervals and thresholds | `object` | n/a | yes |
| firewall_creation_enabled | Create health check and client firewall rules | `bool` | `true` | no |
| ingress_source_ranges | Client ranges allowed to reach the backends | `list(string)` | `["0.0.0.0/0"]` | no |
| target_tags | Backend network tags for the firewall rules | `list(string)` | `[]` | no |
| target_service_accounts | Backend service accounts for the firewall rules | `list(string)` | `[]` | no |
| logging_enabled | Connection logs in Cloud Logging | `bool` | `false` | no |
| logging_sample_rate | Fraction of connections logged | `number` | `1` | no |

## Outputs

| Name | Description |
| --- | --- |
| project_id | Project ID |
| region | Region |
| ip_address | Address clients connect to |
| ip_address_self_link | Reserved address self link |
| forwarding_rule_id / forwarding_rule_self_link | Forwarding rule |
| backend_service_id / backend_service_self_link | Regional backend service |
| health_check_id | Regional health check |
| firewall_rule_names | Firewall rules created |

## Testing

```bash
tofu init -backend=false
tofu test
```
