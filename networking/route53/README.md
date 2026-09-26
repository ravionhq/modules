# Route53 Module

Manage AWS Route53 hosted zones and their DNS records. Supports creating new
public or private hosted zones, or managing records in an existing zone. Also
supports optional VPC associations, query logging, and DNSSEC signing.

## Features

- Create a public or private hosted zone, or reference an existing one
- Manage DNS records of any common type (A, AAAA, CNAME, MX, TXT, SRV, CAA, NS, PTR, NAPTR, SOA, SPF, DS)
- Alias records for AWS resources (ALB, CloudFront, API Gateway, S3, etc.)
- Routing policies: weighted, failover, latency, geolocation, multivalue-answer
- VPC associations for private hosted zones (including additional associations across accounts/regions)
- Optional query logging to CloudWatch Logs
- Optional DNSSEC signing with a customer-managed KMS key
- Reusable delegation sets

## Usage

### Minimal: create a public hosted zone

```hcl
module "dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/route53?ref=v1.0.0"

  name = "example.com"

  tags = {
    Environment = "production"
  }
}
```

### Public hosted zone with records

```hcl
module "dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/route53?ref=v1.0.0"

  name = "example.com"

  records = [
    {
      name = "example.com"
      type = "A"
      alias = {
        name                   = module.alb.alb_dns_name
        zone_id                = module.alb.alb_zone_id
        evaluate_target_health = true
      }
    },

    {
      name    = "www.example.com"
      type    = "CNAME"
      ttl     = 300
      records = ["example.com"]
    },

    {
      name    = "example.com"
      type    = "TXT"
      ttl     = 300
      records = ["v=spf1 -all"]
    },

    {
      name = "example.com"
      type = "MX"
      ttl  = 300
      records = [
        "10 inbound-smtp.us-east-1.amazonaws.com",
      ]
    }
  ]
}
```

Long ASCII TXT and SPF values are split into 255-byte character strings automatically. To split a
value manually, use the AWS provider's internal quote separator without surrounding quotes, for
example `first-part" "second-part`.

### Manage records in an existing hosted zone

```hcl
module "app_dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/route53?ref=v1.0.0"

  zone_creation_enabled = false
  zone_id     = "Z1234567890ABC"

  records = [
    {
      name    = "api.example.com"
      type    = "A"
      ttl     = 60
      records = ["192.0.2.10"]
    }
  ]
}
```

### Private hosted zone

```hcl
module "internal_dns" {
  source = "git::https://github.com/ravionhq/modules.git//networking/route53?ref=v1.0.0"

  name         = "internal.example.com"
  private_zone_enabled = true

  vpc_associations = {
    primary = {
      vpc_id     = module.vpc.vpc_id
      vpc_region = "us-east-1"
    }
  }

  records = [
    {
      name    = "db.internal.example.com"
      type    = "CNAME"
      ttl     = 60
      records = [module.rds.endpoint]
    }
  ]
}
```

### Weighted routing (blue/green)

```hcl
module "dns" {
  source = "..."

  name = "example.com"

  records = [
    {
      name           = "api.example.com"
      type           = "A"
      set_identifier = "blue"
      weighted_routing_policy = {
        weight = 90
      }
      alias = {
        name                   = module.alb_blue.alb_dns_name
        zone_id                = module.alb_blue.alb_zone_id
        evaluate_target_health = true
      }
    },

    {
      name           = "api.example.com"
      type           = "A"
      set_identifier = "green"
      weighted_routing_policy = {
        weight = 10
      }
      alias = {
        name                   = module.alb_green.alb_dns_name
        zone_id                = module.alb_green.alb_zone_id
        evaluate_target_health = true
      }
    }
  ]
}
```

### Query logging

Query logging is supported for public hosted zones. By default, the module
creates the CloudWatch log group and resource policy in `us-east-1`, where
Route53 requires query logging destinations and permissions.

```hcl
module "dns" {
  source = "..."

  name                 = "example.com"
  query_logging_enabled = true
}
```

To reuse an existing `us-east-1` log group, disable log group creation and pass
its ARN. The module still creates the resource policy that allows Route53 to
write logs.

```hcl
module "dns" {
  source = "..."

  name                             = "example.com"
  query_logging_enabled            = true
  query_log_group_creation_enabled = false
  query_log_group_arn              = aws_cloudwatch_log_group.dns_queries.arn
}
```

### DNSSEC

DNSSEC signing requires a customer-managed KMS key in `us-east-1` with the
appropriate key policy for Route53. After the module is applied, publish the
`dnssec_ds_record` output to the parent zone (registrar).

```hcl
module "dns" {
  source = "..."

  name               = "example.com"
  dnssec_enabled      = true
  dnssec_kms_key_arn = aws_kms_key.dnssec.arn
}

output "ds_record" {
  value = module.dns.dnssec_ds_record
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| tags | A map of tags to assign to the hosted zone | `map(string)` | `{}` | no |

### Hosted Zone

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| zone_creation_enabled | If true, create a new hosted zone; if false, reference an existing zone via `zone_id` | `bool` | `true` | no |
| zone_id | ID of an existing hosted zone to manage records in (required when `zone_creation_enabled = false`) | `string` | `null` | conditional |
| name | FQDN for the hosted zone (required when `zone_creation_enabled = true`) | `string` | `null` | conditional |
| comment | Comment for the hosted zone | `string` | `"Managed by Terraform"` | no |
| record_force_destroy_enabled | Destroy all records when the zone is destroyed | `bool` | `false` | no |
| delegation_set_id | Reusable delegation set ID (public zones only) | `string` | `null` | no |

### Private Zone

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| private_zone_enabled | Whether the created zone is private | `bool` | `false` | no |
| vpc_associations | Map of VPCs to associate with the private zone | `map(object)` | `{}` | no |

Each entry in `vpc_associations` supports:

| Key | Description | Type | Required |
|-----|-------------|------|----------|
| vpc_id | The ID of the VPC to associate | `string` | yes |
| vpc_region | The region of the VPC | `string` | no |

### Records

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| records | List of DNS records to manage | `list(object)` | `[]` | no |

Each record supports:

| Key | Description | Type | Required |
|-----|-------------|------|----------|
| name | The record name (FQDN or relative to the zone) | `string` | yes |
| type | Record type: `A`, `AAAA`, `CNAME`, `CAA`, `MX`, `NAPTR`, `NS`, `PTR`, `SOA`, `SPF`, `SRV`, `TXT`, `DS` | `string` | yes |
| ttl | TTL in seconds (required unless using `alias`) | `number` | conditional |
| records | Record values (required unless using `alias`). CNAME and SOA records must have exactly one value. Long TXT and SPF values are split into 255-character strings automatically; see [Long record values](#long-record-values). | `list(string)` | conditional |
| alias | Alias target `{ name, zone_id, evaluate_target_health }` (use instead of `ttl`/`records`). `name` is the AWS target DNS name. `zone_id` is the AWS target resource hosted zone ID, not this domain's hosted zone ID. For ALB/NLB use the load balancer canonical hosted zone ID; for CloudFront use `Z2FDTNDATAQYW2`; API Gateway and S3 website endpoints use service and region-specific IDs. | `object` | conditional |
| set_identifier | Unique ID for routing-policy records | `string` | no |
| health_check_id | Route53 health check ID | `string` | no |
| allow_overwrite | Allow creation to overwrite an existing record | `bool` | no |
| weighted_routing_policy | `{ weight }` block | `object` | no |
| failover_routing_policy | `{ type }` (PRIMARY or SECONDARY) | `object` | no |
| latency_routing_policy | `{ region }` | `object` | no |
| geolocation_routing_policy | `{ continent, country, subdivision }` | `object` | no |
| multivalue_answer_routing_policy | Enable multivalue answer routing | `bool` | no |

#### Long record values

Route53 accepts at most 255 characters per character string in a record value, and at
most 65535 bytes across all values of a single record. `TXT` and `SPF` values are
allowed to be a sequence of quoted strings that resolvers rejoin, so this module splits
oversized `TXT` and `SPF` values into 255-character quoted strings automatically. Pass a
DKIM key or long SPF record exactly as your provider gives it to you:

```hcl
records = [
  {
    name    = "selector._domainkey.example.com"
    type    = "TXT"
    ttl     = 300
    records = ["v=DKIM1; k=rsa; p=<full 400-character key>"]
  }
]

# sent to Route53 as: "v=DKIM1; k=rsa; p=<first 255 characters>" "<remaining characters>"
```

Values that already contain quotes are used exactly as written, so you can control the
split yourself. For record types that cannot be expressed as multiple character strings,
a value longer than 255 characters fails during planning with an explanatory message
instead of failing the apply. Unbalanced quotes and oversized total record data are
validated the same way.

### Query Logging

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| query_logging_enabled | Enable Route53 query logging | `bool` | `false` | no |
| query_log_group_creation_enabled | Create the CloudWatch Logs log group and resource policy in `us-east-1` | `bool` | `true` | no |
| query_log_group_name | Name for the created CloudWatch Logs log group | `string` | `null` | no |
| query_log_group_retention_days | Number of days to retain query logs; use `0` to retain indefinitely | `number` | `90` | no |
| query_log_resource_policy_name | Name for the CloudWatch Logs resource policy | `string` | `null` | no |
| query_log_group_arn | ARN of an existing destination CloudWatch log group when creation is disabled | `string` | `null` | conditional |

### DNSSEC

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| dnssec_enabled | Enable DNSSEC signing | `bool` | `false` | no |
| dnssec_kms_key_arn | KMS key ARN in `us-east-1` used for signing | `string` | `null` | conditional |
| dnssec_signing_status | `SIGNING` or `NOT_SIGNING` | `string` | `"SIGNING"` | no |

## Outputs

| Name | Description |
|------|-------------|
| zone_id | The ID of the hosted zone |
| zone_arn | The ARN of the hosted zone (null when referencing existing) |
| zone_name | The name of the hosted zone |
| name_servers | The name servers assigned to the zone |
| primary_name_server | The primary name server of the zone |
| is_private_zone | Whether the zone is private |
| record_names | Map of record keys to FQDNs |
| record_ids | Map of record keys to Route53 record IDs |
| dnssec_key_signing_key_id | The ID of the KSK (null when DNSSEC disabled) |
| dnssec_ds_record | The DS record to publish to the parent zone |
| query_log_id | The ID of the query log configuration |
| query_log_group_arn | The ARN of the CloudWatch Logs log group used for query logs |
| query_log_group_name | The name of the CloudWatch Logs log group used for query logs |

## Notes

- Route53 hosted zones are global; the provider region does not affect zone
  placement, but DNSSEC KMS keys and public-zone query log groups must live in
  `us-east-1`.
- For private zones, the initial VPC associations are attached to the zone
  resource directly. To associate additional VPCs (including cross-account
  VPCs), use the `aws_route53_vpc_association_authorization` /
  `aws_route53_zone_association` resources outside the module.
- When using `zone_creation_enabled = false`, `record_force_destroy_enabled` has no effect and the
  upstream zone is not managed.
- Alias records cannot specify a TTL; TTLs are inherited from the target.
