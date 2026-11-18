# Cloud DNS

Creates a Google Cloud DNS public or private managed zone (or uses an existing one), record sets with simple, weighted round robin, or geolocation routing, query logging (zone logging for public zones, a DNS server policy for private zones), and Google-managed DNSSEC.

This is the Google Cloud counterpart of `networking/route53` and backs the `rvn-gcp-dns` module definition.

## Usage

```hcl
module "dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/gcp_dns?ref=v1.0.0"

  project_id     = "acme-prod-123"
  dns_name       = "example.com"
  dnssec_enabled = true

  records = [
    { name = "@", type = "A", rrdatas = ["203.0.113.10"] },
    { name = "www", type = "CNAME", rrdatas = ["example.com."] },
    {
      name = "api"
      type = "A"
      routing_policy = {
        type = "WEIGHTED"
        items = [
          { key = "blue", weight = 90, rrdatas = ["203.0.113.10"] },
          { key = "green", weight = 10, rrdatas = ["203.0.113.20"] },
        ]
      }
    },
  ]
}

# Private zone visible to a network
module "internal_dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/gcp_dns?ref=v1.0.0"

  project_id                  = "acme-prod-123"
  dns_name                    = "internal.example.com"
  private_zone_enabled        = true
  private_visibility_networks = [module.network.network_id]
  query_logging_enabled       = true
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
| project_id | Project that owns the zone | `string` | n/a | yes |
| region | Provider default region (zones are global) | `string` | `null` | no |
| labels | Labels for the zone (sanitized to GCP label rules) | `map(string)` | `{}` | no |
| zone_creation_enabled | Create a zone; false to use `zone_name` | `bool` | `true` | no |
| zone_name | Zone resource name; required for an existing zone, derived from `dns_name` otherwise | `string` | `null` | no |
| dns_name | Domain the created zone serves | `string` | `null` | when creating |
| description | Zone description | `string` | `"Managed in Ravion"` | no |
| record_force_destroy_enabled | Delete all records when the zone is destroyed | `bool` | `false` | no |
| private_zone_enabled | Create a private zone | `bool` | `false` | no |
| private_visibility_networks | Network self links or IDs for a private zone | `list(string)` | `[]` | for private zones |
| records | Record sets (`name`, `type`, `ttl`, `rrdatas` or `routing_policy`) | `list(object)` | `[]` | no |
| dnssec_enabled | DNSSEC signing for a public zone | `bool` | `false` | no |
| dnssec_non_existence | `nsec3` or `nsec` | `string` | `"nsec3"` | no |
| query_logging_enabled | Log queries to Cloud Logging | `bool` | `false` | no |
| server_policy_name | Server policy name for private-zone logging | `string` | `null` | no |

## Outputs

| Name | Description |
| --- | --- |
| project_id | Project that owns the zone |
| zone_name | Zone resource name |
| zone_id | Zone ID (`projects/<p>/managedZones/<name>`) |
| dns_name | Domain with a trailing dot |
| name_servers | Name servers to delegate to |
| is_private_zone | Whether the zone is private |
| record_names | Map of record keys to fully qualified names |
| dnssec_ds_records | DS records to publish at the registrar |
| server_policy_name | Server policy created for private-zone logging |

## Testing

```bash
tofu init -backend=false
tofu test
```
