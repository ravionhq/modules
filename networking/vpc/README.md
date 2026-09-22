# AWS VPC Module

This module creates a production-ready AWS VPC with public and private subnets, optional NAT Gateway, IPv6 support, and VPC Flow Logs.

## Features

- Configurable VPC CIDR block with DNS support and hostnames enabled by default
- Public and private subnets across up to 3 availability zones by default, capped by the AZs available to the selected account and region
- Automatic or custom subnet CIDR allocation using cidrsubnet function
- Optional NAT Gateway (single or per-AZ for high availability)
- Optional VPC endpoints: free S3/DynamoDB gateway endpoints and interface endpoints (PrivateLink) with a shared security group
- Optional IPv6 support with Amazon-provided CIDR and Egress-Only Internet Gateway
- Optional VPC Flow Logs to CloudWatch or S3 with configurable retention
- Optional VPC peering with one or more existing VPCs (same- or cross-account/region)
- Internet Gateway for public subnet internet access
- Route tables with automatic association and IPv6 routing support
- Comprehensive tagging with ManagedBy and Module defaults

## Usage

### Basic Usage

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"
}
```

By default, the module creates up to 3 public/private subnet pairs. If the selected account and region expose only 2 availability zones, the default automatically falls back to 2 subnet pairs.

### With NAT Gateway (Single - Cost Effective)

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                = "my-vpc"
  vpc_cidr            = "10.0.0.0/16"
  nat_gateway_enabled = true
  # nat_gateway_high_availability_enabled defaults to false: single NAT for all private subnets
}
```

### With NAT Gateway (High Availability)

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                                  = "my-vpc"
  vpc_cidr                              = "10.0.0.0/16"
  nat_gateway_enabled                   = true
  nat_gateway_high_availability_enabled = true # One NAT per AZ for high availability
}
```

When `nat_gateway_high_availability_enabled = true`, the module creates one NAT Gateway per AZ and one private route table per AZ, with each private subnet routed through the NAT Gateway in its own AZ. This avoids cross-AZ data transfer charges for outbound internet traffic from private subnets.

### With Reserved (Pre-allocated) Elastic IPs

Allocate the EIPs in a separate module so they survive VPC replacements (useful for partner allowlists or firewall rules that must not change), then pass them in:

```hcl
module "nat_eips" {
  source = "git::https://github.com/ravionhq/modules.git//networking/eips?ref=v1.0.0"

  name      = "prod-nat"
  eip_count = 3 # one per resolved subnet AZ
}

module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                                  = "prod"
  vpc_cidr                              = "10.0.0.0/16"
  subnet_count                          = 3
  nat_gateway_enabled                   = true
  nat_gateway_high_availability_enabled = true # one NAT per AZ

  nat_gateway_eip_allocation_ids = module.nat_eips.allocation_ids
}
```

The list length must equal `1` when `nat_gateway_high_availability_enabled = false`, or the resolved subnet count when `nat_gateway_high_availability_enabled = true`. EIP allocations are consumed in order, so `allocation_ids[i]` is attached to the NAT Gateway in `availability_zones[i]`.

### With VPC Endpoints

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"

  # Free gateway endpoints — keep S3/DynamoDB traffic off the NAT gateway
  vpc_endpoint_s3_gateway_enabled       = true
  vpc_endpoint_dynamodb_gateway_enabled = true

  # Interface endpoints (PrivateLink) — private access to AWS services,
  # billed per hour per AZ plus per GB processed
  vpc_endpoint_interface_services = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
  ]
}
```

Gateway endpoints add routes to all of this VPC's route tables and are free. Interface endpoints are placed in every private subnet with private DNS enabled and share a module-managed security group allowing HTTPS (443) from the VPC CIDR. Pulling ECR images privately requires `ecr.api`, `ecr.dkr`, and the S3 gateway endpoint together.

### With IPv6 Support

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name         = "my-vpc"
  vpc_cidr     = "10.0.0.0/16"
  ipv6_enabled = true
}
```

### With VPC Flow Logs to CloudWatch

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                     = "my-vpc"
  vpc_cidr                 = "10.0.0.0/16"
  flow_logs_enabled        = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 30
}
```

### With VPC Flow Logs to S3 (New Bucket)

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                  = "my-vpc"
  vpc_cidr              = "10.0.0.0/16"
  flow_logs_enabled     = true
  flow_logs_destination = "s3"
  # A new S3 bucket will be created automatically
}
```

### With VPC Flow Logs to S3 (Existing Bucket)

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                    = "my-vpc"
  vpc_cidr                = "10.0.0.0/16"
  flow_logs_enabled       = true
  flow_logs_destination   = "s3"
  flow_logs_s3_bucket_arn = "arn:aws:s3:::my-existing-flow-logs-bucket"
}
```

### With VPC Peering to an Existing VPC (Same Account, Same Region)

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"

  vpc_peering_connections = {
    shared-services = {
      peer_vpc_id      = "vpc-0123456789abcdef0"
      peer_cidr_blocks = ["10.50.0.0/16"]

      # Optionally manage return routes on the peer VPC's route tables.
      # Only valid for same-account, same-region peerings.
      peer_route_table_ids = [
        "rtb-0aaaa1111bbbb2222c",
        "rtb-0aaaa1111bbbb3333d",
      ]
    }
  }
}
```

This creates the peering connection, auto-accepts it, and adds routes to both the
public and private route tables in this VPC for the peer CIDR. When
`peer_route_table_ids` is provided, the module also adds return routes
(`destination = this VPC's CIDR`, `target = the peering connection`) to each of the
specified peer route tables.

### With VPC Peering Across Accounts or Regions

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"

  vpc_peering_connections = {
    prod-east = {
      peer_vpc_id      = "vpc-0fedcba9876543210"
      peer_cidr_blocks = ["10.100.0.0/16"]
      peer_owner_id    = "111122223333" # Different AWS account
      peer_region      = "us-east-1"    # Different region
    }
  }
}
```

For cross-account or cross-region peerings, `auto_accept` is ignored and the peering
will be in `pending-acceptance` status until the owner of the peer VPC accepts it
(via `aws_vpc_peering_connection_accepter` or the AWS console). The peer's return
routes also need to be managed from the peer side (this module does not support
`peer_route_table_ids` in that case, since the AWS provider used here cannot reach
the peer's route tables).

### Multiple Peering Connections with Custom Routing

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"

  vpc_peering_connections = {
    shared-services = {
      peer_vpc_id                       = "vpc-0123456789abcdef0"
      peer_cidr_blocks                  = ["10.50.0.0/16"]
      remote_vpc_dns_resolution_enabled = true
    }
    data-platform = {
      peer_vpc_id                       = "vpc-0aaaa1111bbbb2222c"
      peer_cidr_blocks                  = ["10.60.0.0/16", "10.61.0.0/16"]
      public_route_table_routes_enabled = false # Only add routes to private route tables
    }
  }
}
```

### Custom Subnet Configuration

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name         = "my-vpc"
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 3

  # Custom CIDRs (must match subnet_count)
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

  # Specific availability zones
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

### Full Example

```hcl
module "vpc" {
  source = "git::https://github.com/ravionhq/modules.git//networking/vpc?ref=v1.0.0"

  name                  = "production"
  vpc_cidr              = "10.0.0.0/16"
  subnet_count          = 3
  dns_support_enabled   = true
  dns_hostnames_enabled = true

  # NAT Gateway
  nat_gateway_enabled                   = true
  nat_gateway_high_availability_enabled = true # HA: one NAT per AZ

  # IPv6
  ipv6_enabled = true

  # Flow Logs
  flow_logs_enabled        = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 90
  flow_logs_traffic_type   = "ALL"

  tags = {
    Environment = "production"
    Project     = "my-project"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module (1-36 characters) | `string` | n/a | yes |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |

### VPC Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_cidr | The IPv4 CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| dns_support_enabled | Enable DNS support in the VPC | `bool` | `true` | no |
| dns_hostnames_enabled | Enable DNS hostnames in the VPC | `bool` | `true` | no |

### Subnets

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subnet_count | The number of public and private subnet pairs to create (1-6). If null, creates up to 3 pairs, capped by selected or available AZs | `number` | `null` | no |
| availability_zones | A list of availability zones to use for subnets. If empty, AZs will be automatically selected | `list(string)` | `[]` | no |
| public_subnet_cidrs | A list of CIDR blocks for public subnets. If null, CIDRs will be automatically calculated | `list(string)` | `null` | no |
| private_subnet_cidrs | A list of CIDR blocks for private subnets. If null, CIDRs will be automatically calculated | `list(string)` | `null` | no |

### NAT Gateway

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| nat_gateway_enabled | Enable NAT Gateway(s) to allow private subnets to access the internet | `bool` | `false` | no |
| nat_gateway_high_availability_enabled | Deploy one NAT Gateway per AZ for high availability. Set to false (default) to use a single NAT Gateway for all private subnets (cost-effective) | `bool` | `false` | no |
| single_nat_gateway | **DEPRECATED** — use `nat_gateway_high_availability_enabled` (inverted). When set non-null, takes precedence | `bool` | `null` | no |
| nat_gateway_eip_allocation_ids | Pre-allocated EIP allocation IDs to attach to the NAT Gateway(s). When null, the module allocates new EIPs internally. Length must equal 1 when `nat_gateway_high_availability_enabled = false`, or the resolved subnet count when `true` | `list(string)` | `null` | no |

### VPC Endpoints

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_endpoint_s3_gateway_enabled | Create a free S3 gateway VPC endpoint attached to all route tables | `bool` | `false` | no |
| vpc_endpoint_dynamodb_gateway_enabled | Create a free DynamoDB gateway VPC endpoint attached to all route tables | `bool` | `false` | no |
| vpc_endpoint_interface_services | AWS service short names to create interface VPC endpoints for (e.g. `["ecr.api", "ecr.dkr", "logs"]`). Placed in every private subnet with private DNS enabled and a shared security group allowing HTTPS from the VPC CIDR | `list(string)` | `[]` | no |

### IPv6

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ipv6_enabled | Enable IPv6 support for the VPC. An Amazon-provided IPv6 CIDR block will be assigned | `bool` | `false` | no |

### VPC Flow Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| flow_logs_enabled | Enable VPC Flow Logs for network traffic monitoring | `bool` | `false` | no |
| flow_logs_destination | The destination for VPC Flow Logs. Valid values: 'cloudwatch' or 's3' | `string` | `"cloudwatch"` | no |
| flow_logs_s3_bucket_arn | The ARN of an existing S3 bucket for VPC Flow Logs. If null and destination is 's3', a new bucket will be created | `string` | `null` | no |
| flow_logs_retention_days | The number of days to retain VPC Flow Logs in CloudWatch. Set to 0 for indefinite retention | `number` | `30` | no |
| flow_logs_traffic_type | The type of traffic to capture in VPC Flow Logs. Valid values: 'ACCEPT', 'REJECT', or 'ALL' | `string` | `"ALL"` | no |
| flow_logs_kms_key_id | KMS key ID for S3 bucket encryption. If null, uses AES256 (SSE-S3) | `string` | `null` | no |
| flow_logs_versioning_enabled | Enable versioning for the flow logs S3 bucket | `bool` | `false` | no |

### VPC Peering

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_peering_connections | Map of VPC peering connections to create from this VPC to existing VPCs. See below for the object schema | `map(object({...}))` | `{}` | no |

Each entry in `vpc_peering_connections` accepts the following attributes:

| Attribute | Description | Type | Default | Required |
|-----------|-------------|------|---------|----------|
| peer_vpc_id | The ID of the existing VPC to peer with | `string` | n/a | yes |
| peer_cidr_blocks | CIDR blocks of the peer VPC. Routes are added in this VPC's route tables for each CIDR pointing at the peering connection | `list(string)` | n/a | yes |
| peer_owner_id | AWS account ID that owns the peer VPC. Required for cross-account peering | `string` | `null` | no |
| peer_region | AWS region of the peer VPC. Required for cross-region peering | `string` | `null` | no |
| auto_accept | Whether to auto-accept the peering. Only valid for same-account, same-region peerings | `bool` | `true` | no |
| remote_vpc_dns_resolution_enabled | Allow DNS resolution of private hostnames in the peer VPC. Only valid for same-account, same-region peerings | `bool` | `false` | no |
| public_route_table_routes_enabled | Add routes for `peer_cidr_blocks` to this VPC's public route table | `bool` | `true` | no |
| private_route_table_routes_enabled | Add routes for `peer_cidr_blocks` to this VPC's private route table(s) | `bool` | `true` | no |
| peer_route_table_ids | Optional list of route table IDs in the peer VPC to add return routes to (destination = this VPC's CIDR). Only supported for same-account, same-region peerings | `list(string)` | `[]` | no |
| tags | Additional tags to apply to the peering connection | `map(string)` | `{}` | no |

> **Note:** For cross-account or cross-region peerings, this module cannot manage the peer VPC's route tables (the AWS provider used here doesn't have access to them). The peer VPC's owner is responsible for adding return routes and accepting the peering request (e.g. via `aws_vpc_peering_connection_accepter`).

## Outputs

### VPC

| Name | Description |
|------|-------------|
| vpc_id | The ID of the VPC |
| vpc_arn | The ARN of the VPC |
| vpc_cidr_block | The IPv4 CIDR block of the VPC |
| vpc_ipv6_cidr_block | The IPv6 CIDR block of the VPC (if IPv6 is enabled) |

### Subnets

| Name | Description |
|------|-------------|
| public_subnet_ids | List of IDs of public subnets |
| private_subnet_ids | List of IDs of private subnets |
| public_subnet_cidrs | List of IPv4 CIDR blocks of public subnets |
| private_subnet_cidrs | List of IPv4 CIDR blocks of private subnets |
| public_subnet_ipv6_cidrs | List of IPv6 CIDR blocks of public subnets (if IPv6 is enabled) |
| private_subnet_ipv6_cidrs | List of IPv6 CIDR blocks of private subnets (if IPv6 is enabled) |
| public_subnet_arns | List of ARNs of public subnets |
| private_subnet_arns | List of ARNs of private subnets |
| availability_zones | List of availability zones used for subnets |

### Internet Gateway

| Name | Description |
|------|-------------|
| internet_gateway_id | The ID of the Internet Gateway |
| internet_gateway_arn | The ARN of the Internet Gateway |

### NAT Gateway

| Name | Description |
|------|-------------|
| nat_gateway_ids | List of NAT Gateway IDs (if NAT Gateway is enabled) |
| nat_gateway_public_ips | List of public IP addresses of NAT Gateways (if NAT Gateway is enabled) |
| nat_gateway_allocation_ids | List of Elastic IP allocation IDs for NAT Gateways (if NAT Gateway is enabled) |

### Route Tables

| Name | Description |
|------|-------------|
| public_route_table_id | The ID of the public route table |
| private_route_table_ids | List of IDs of private route tables |

### VPC Endpoints

| Name | Description |
|------|-------------|
| vpc_endpoint_s3_id | The ID of the S3 gateway VPC endpoint (if enabled) |
| vpc_endpoint_dynamodb_id | The ID of the DynamoDB gateway VPC endpoint (if enabled) |
| vpc_endpoint_interface_ids | Map of interface VPC endpoint service short names to their endpoint IDs |
| vpc_endpoints_security_group_id | The ID of the shared security group for interface VPC endpoints (if any interface endpoints are created) |

### Egress-Only Internet Gateway (IPv6)

| Name | Description |
|------|-------------|
| egress_only_internet_gateway_id | The ID of the Egress-Only Internet Gateway (if IPv6 is enabled) |

### VPC Flow Logs

| Name | Description |
|------|-------------|
| flow_log_id | The ID of the VPC Flow Log (if flow logs are enabled) |
| flow_log_cloudwatch_log_group_name | The name of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch) |
| flow_log_cloudwatch_log_group_arn | The ARN of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch) |
| flow_log_cloudwatch_iam_role_arn | The ARN of the IAM Role for VPC Flow Logs to CloudWatch (if destination is cloudwatch) |
| flow_log_s3_bucket_arn | The ARN of the S3 bucket for VPC Flow Logs (if destination is s3) |

### VPC Peering

| Name | Description |
|------|-------------|
| vpc_peering_connection_ids | Map of VPC peering connection logical names to their connection IDs |
| vpc_peering_connection_accept_statuses | Map of VPC peering connection logical names to their acceptance status |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                    VPC                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                         Internet Gateway                                │  │
│  │  • Routes 0.0.0.0/0 for public subnets                                 │  │
│  │  • Routes ::/0 for IPv6 (if enabled)                                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                       Public Subnets (1-6 AZs)                          │  │
│  │  • No automatic public IPv4                  • Direct internet access  │  │
│  │  • Shared route table (public)               • IPv6 enabled (optional) │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │     NAT Gateway(s)   │  │  Egress-Only IGW     │  │   Elastic IPs      │  │
│  │  (if enabled)        │  │  (if IPv6 enabled)   │  │   (for NAT GWs)    │  │
│  │  • Single or per-AZ  │  │  • IPv6 egress only  │  │                    │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                       Private Subnets (1-6 AZs)                         │  │
│  │  • No public IPs                             • NAT for outbound IPv4   │  │
│  │  • 1 or N route tables                       • EIGW for outbound IPv6  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                          VPC Flow Logs                                  │  │
│  │  • CloudWatch Logs (Log Group + IAM Role) or S3 Bucket                 │  │
│  │  • Configurable retention and traffic type                             │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        NETWORKING/VPC TERRAFORM MODULE                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │       VPC CONFIGURATION         │   │            SUBNETS                      │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required, 1-36 ch)  │   │ • vpc_cidr (10.0.0.0/16)        │   │ • subnet_count (auto, max 3 by default)│  ║
║  │ • tags                      │   │ • dns_support_enabled (true)   │   │ • availability_zones                    │  ║
║  └──────────────┬──────────────┘   │ • dns_hostnames_enabled (true) │   │ • public_subnet_cidrs                   │  ║
║                 │                  └─────────────────────────────────┘   │ • private_subnet_cidrs                  │  ║
║                 │                                                         └─────────────────────────────────────────┘  ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "networking/vpc" }                                   │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │ • subnet_count = var.subnet_count or min(3, selected availability zone count)                             │   │  ║
║  │  │ • azs = selected availability zones sliced to subnet_count                                                 │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ SUBNET CIDR CALCULATION:                                                                                   │   │  ║
║  │  │ • public_subnet_cidrs  = cidrsubnet(vpc_cidr, 8, i + 1)   # 10.0.1.0/24, 10.0.2.0/24, ...                 │   │  ║
║  │  │ • private_subnet_cidrs = cidrsubnet(vpc_cidr, 8, i + 11)  # 10.0.11.0/24, 10.0.12.0/24, ...               │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • nat_gateway_count = nat_gateway_enabled ? (nat_gateway_high_availability_enabled ? subnet_count : 1) : 0 │   │  ║
║  │  │ • create_flow_log_cloudwatch = flow_logs_enabled && flow_logs_destination == "cloudwatch"                  │   │  ║
║  │  │ • create_flow_log_s3 = flow_logs_enabled && flow_logs_destination == "s3"                                  │   │  ║
║  │  │ • create_flow_log_s3_bucket = create_flow_log_s3 && flow_logs_s3_bucket_arn == null                       │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       NAT GATEWAY           │   │           IPv6                  │   │           VPC FLOW LOGS                 │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • nat_gateway_enabled       │   │ • ipv6_enabled                  │   │ • flow_logs_enabled                     │  ║
║  │ • nat_gateway_ha_enabled    │   │                                 │   │ • flow_logs_destination                 │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   │ • flow_logs_s3_bucket_arn               │  ║
║                                                                          │ • flow_logs_retention_days              │  ║
║                                                                          │ • flow_logs_traffic_type                │  ║
║                                                                          │ • flow_logs_kms_key_id                  │  ║
║                                                                          │ • flow_logs_versioning_enabled          │  ║
║                                                                          └─────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                         aws_vpc.this                                                         │    ║
║    │                                        (CORE RESOURCE)                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ • cidr_block = var.vpc_cidr                           • enable_dns_support = var.dns_support_enabled        │    ║
║    │ • enable_dns_hostnames = var.dns_hostnames_enabled   • assign_generated_ipv6_cidr_block = var.ipv6_enabled │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────────┐                ║
║           │                                               │                                           │                ║
║           ▼                                               ▼                                           ▼                ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │  aws_internet_gateway.this   │    │  aws_subnet.public (count)   │    │  aws_subnet.private (count)  │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • Attached to VPC            │    │ • Per AZ (subnet_count)      │    │ • Per AZ (subnet_count)      │          ║
║    │ • Enables public internet    │    │ • Auto-calculated or custom  │    │ • Auto-calculated or custom  │          ║
║    │   access                     │    │   CIDR blocks                │    │   CIDR blocks                │          ║
║    │                              │    │ • No automatic public IPv4   │    │ • No public IP               │          ║
║    │                              │    │ • IPv6 CIDR (if enabled)     │    │ • IPv6 CIDR (if enabled)     │          ║
║    └──────────────┬───────────────┘    └──────────────┬───────────────┘    └──────────────┬───────────────┘          ║
║                   │                                   │                                   │                            ║
║                   ▼                                   ▼                                   ▼                            ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │  aws_route_table.public      │    │  aws_route_table_association │    │  aws_route_table.private     │          ║
║    ├──────────────────────────────┤    │        .public (count)       │    │         (1 or count)         │          ║
║    │ • 0.0.0.0/0 → IGW            │    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • ::/0 → IGW (if IPv6)       │    │ • Associates public subnets  │    │ • 1 table if single_nat_gw   │          ║
║    └──────────────────────────────┘    │   to public route table      │    │ • N tables if multi-NAT      │          ║
║                                        └──────────────────────────────┘    └──────────────┬───────────────┘          ║
║                                                                                           │                            ║
║           ┌───────────────────────────────────────────────────────────────────────────────┤                            ║
║           │                                                                               │                            ║
║           ▼                                                                               ▼                            ║
║    ┌──────────────────────────────┐                                        ┌──────────────────────────────┐          ║
║    │  aws_eip.nat (0, 1, or N)    │                                        │  aws_route_table_association │          ║
║    ├──────────────────────────────┤                                        │        .private (count)      │          ║
║    │ • Elastic IPs for NAT GWs    │                                        ├──────────────────────────────┤          ║
║    │ • domain = "vpc"             │                                        │ • Associates private subnets │          ║
║    └──────────────┬───────────────┘                                        │   to private route table(s)  │          ║
║                   │                                                        └──────────────────────────────┘          ║
║                   ▼                                                                                                    ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │ aws_nat_gateway.this         │    │  aws_route.private_nat       │    │ aws_egress_only_internet     │          ║
║    │      (0, 1, or N)            │    │       (0, 1, or N)           │    │    _gateway.this (0 or 1)    │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • 1 if HA disabled (default) │    │ • 0.0.0.0/0 → NAT Gateway    │    │ • Only if ipv6_enabled       │          ║
║    │ • N if multi-NAT (per AZ)    │    │ • Associates private route   │    │ • Allows IPv6 egress only    │          ║
║    │ • Placed in public subnets   │    │   tables with NAT GWs        │    │   from private subnets       │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                                                                                        ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐                                               ║
║    │ aws_route.private_ipv6       │    │ aws_route.public_internet    │                                               ║
║    │     _egress (0, 1, or N)     │    │        _ipv6 (0 or 1)        │                                               ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤                                               ║
║    │ • ::/0 → Egress-Only IGW     │    │ • ::/0 → Internet Gateway    │                                               ║
║    │ • Only if ipv6_enabled       │    │ • Only if ipv6_enabled       │                                               ║
║    └──────────────────────────────┘    └──────────────────────────────┘                                               ║
║                                                                                                                        ║
║  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │                                         VPC FLOW LOGS RESOURCES                                                 │   ║
║  ├────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │                                                                                                                 │   ║
║  │  CLOUDWATCH DESTINATION (if flow_logs_destination = "cloudwatch"):                                              │   ║
║  │  ┌──────────────────────────────┐  ┌──────────────────────────────┐  ┌──────────────────────────────┐          │   ║
║  │  │ aws_cloudwatch_log_group     │  │ aws_iam_role.flow_logs       │  │ aws_flow_log.cloudwatch      │          │   ║
║  │  │       .flow_logs[0]          │  │           [0]                │  │           [0]                │          │   ║
║  │  ├──────────────────────────────┤  ├──────────────────────────────┤  ├──────────────────────────────┤          │   ║
║  │  │ • /aws/vpc-flow-logs/{name}  │  │ • Assume role policy for     │  │ • Sends logs to CloudWatch   │          │   ║
║  │  │ • Configurable retention     │  │   vpc-flow-logs.amazonaws.com│  │ • Uses IAM role for auth     │          │   ║
║  │  └──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘          │   ║
║  │                                                                                                                 │   ║
║  │  S3 DESTINATION (if flow_logs_destination = "s3"):                                                              │   ║
║  │  ┌──────────────────────────────┐  ┌──────────────────────────────┐  ┌──────────────────────────────┐          │   ║
║  │  │ aws_s3_bucket.flow_logs[0]   │  │ aws_s3_bucket_policy         │  │ aws_flow_log.s3[0]           │          │   ║
║  │  │   (if no existing bucket)    │  │       .flow_logs[0]          │  │                              │          │   ║
║  │  ├──────────────────────────────┤  ├──────────────────────────────┤  ├──────────────────────────────┤          │   ║
║  │  │ • Public access blocked      │  │ • Allows log delivery svc    │  │ • Sends logs to S3 bucket    │          │   ║
║  │  │ • SSE-S3 or KMS encryption   │  │ • GetBucketAcl + PutObject   │  │ • max_aggregation_interval   │          │   ║
║  │  │ • Optional versioning        │  │                              │  │   = 60 seconds               │          │   ║
║  │  │ • Lifecycle rules            │  │                              │  │                              │          │   ║
║  │  └──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘          │   ║
║  └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │                VPC                       │   │              SUBNETS                    │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • vpc_id                                │   │ • public_subnet_ids                     │                            ║
║  │ • vpc_arn                               │   │ • private_subnet_ids                    │                            ║
║  │ • vpc_cidr_block                        │   │ • public_subnet_cidrs                   │                            ║
║  │ • vpc_ipv6_cidr_block                   │   │ • private_subnet_cidrs                  │                            ║
║  └─────────────────────────────────────────┘   │ • public_subnet_ipv6_cidrs              │                            ║
║                                                │ • private_subnet_ipv6_cidrs             │                            ║
║  ┌─────────────────────────────────────────┐   │ • public_subnet_arns                    │                            ║
║  │          INTERNET GATEWAY               │   │ • private_subnet_arns                   │                            ║
║  ├─────────────────────────────────────────┤   │ • availability_zones                    │                            ║
║  │ • internet_gateway_id                   │   └─────────────────────────────────────────┘                            ║
║  │ • internet_gateway_arn                  │                                                                          ║
║  └─────────────────────────────────────────┘   ┌─────────────────────────────────────────┐                            ║
║                                                │           ROUTE TABLES                  │                            ║
║  ┌─────────────────────────────────────────┐   ├─────────────────────────────────────────┤                            ║
║  │            NAT GATEWAY                  │   │ • public_route_table_id                 │                            ║
║  ├─────────────────────────────────────────┤   │ • private_route_table_ids               │                            ║
║  │ • nat_gateway_ids                       │   └─────────────────────────────────────────┘                            ║
║  │ • nat_gateway_public_ips                │                                                                          ║
║  │ • nat_gateway_allocation_ids            │   ┌─────────────────────────────────────────┐                            ║
║  └─────────────────────────────────────────┘   │    EGRESS-ONLY IGW (IPv6)               │                            ║
║                                                ├─────────────────────────────────────────┤                            ║
║  ┌─────────────────────────────────────────┐   │ • egress_only_internet_gateway_id       │                            ║
║  │          VPC FLOW LOGS                  │   └─────────────────────────────────────────┘                            ║
║  ├─────────────────────────────────────────┤                                                                          ║
║  │ • flow_log_id                           │                                                                          ║
║  │ • flow_log_cloudwatch_log_group_name    │                                                                          ║
║  │ • flow_log_cloudwatch_log_group_arn     │                                                                          ║
║  │ • flow_log_cloudwatch_iam_role_arn      │                                                                          ║
║  │ • flow_log_s3_bucket_arn                │                                                                          ║
║  └─────────────────────────────────────────┘                                                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              DATA FLOW DIAGRAM                                                         ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║                                        ┌─────────────────────────┐                                                     ║
║                                        │       var.name          │                                                     ║
║                                        │       var.tags          │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║                                        ┌─────────────────────────┐                                                     ║
║                                        │    local.default_tags   │                                                     ║
║                                        │      local.tags         │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║  var.vpc_cidr ────────────────────────────────────────────────────────────────► aws_vpc.this                          ║
║  var.dns_support_enabled ─────────────────────────────────────────────────────►      │                                ║
║  var.dns_hostnames_enabled ───────────────────────────────────────────────────►      │                                ║
║  var.ipv6_enabled ────────────────────────────────────────────────────────────►      │                                ║
║                                                                                      │                                 ║
║                              ┌────────────────────────┬─────────────────────────────┤                                 ║
║                              │                        │                             │                                 ║
║                              ▼                        ▼                             ▼                                 ║
║              aws_internet_gateway.this     aws_subnet.public[]          aws_subnet.private[]                          ║
║                              │                        │                             │                                 ║
║  local.subnet_count ─────────┼────────────────────────┴─────────────────────────────┤                                 ║
║  var.availability_zones ─────┼────► local.azs ──────────────────────────────────────┤                                 ║
║  var.public_subnet_cidrs ────┼────► local.public_subnet_cidrs ──────────────────────┘                                 ║
║  var.private_subnet_cidrs ───┼────► local.private_subnet_cidrs ─────────────────────                                  ║
║                              │                                                                                        ║
║                              │                        ┌─────────────────────────────────────────────────┐              ║
║                              │                        │                                                 │              ║
║                              ▼                        ▼                                                 ▼              ║
║              aws_route_table.public        aws_route_table.private[]        aws_route_table_association.*             ║
║                              │                        │                                                               ║
║                              │                        │                                                               ║
║  var.nat_gateway_enabled ───┼────────────────────────┼─────────────────────────────────────────────────┐              ║
║  var.nat_gateway_high_availability_enabled ──► local.nat_gateway_count ─────────────────────────────────┤              ║
║                              │                        │                                                 │              ║
║                              │                        ▼                                                 │              ║
║                              │      aws_eip.nat[] ──► aws_nat_gateway.this[] ──► aws_route.private_nat[]│              ║
║                              │                                                                          │              ║
║  var.ipv6_enabled ──────────┴──────────────────────────────────────────────────────────────────────────┤              ║
║                              │                                                                          │              ║
║                              ▼                                                                          ▼              ║
║              aws_egress_only_internet_gateway.this[0] ──────────────────► aws_route.private_ipv6_egress[]             ║
║              aws_route.public_internet_ipv6[0]                                                                        ║
║                                                                                                                        ║
║  var.flow_logs_enabled ────────────────────────────────────────────────────────────────────────────────┐              ║
║  var.flow_logs_destination ────────────────────────────────────────────────────────────────────────────┤              ║
║                              │                                                                          │              ║
║                              │  if "cloudwatch":                                                        │              ║
║                              ├──────────────────► aws_cloudwatch_log_group.flow_logs[0]                 │              ║
║                              │                    aws_iam_role.flow_logs[0]                             │              ║
║                              │                    aws_flow_log.cloudwatch[0]                            │              ║
║                              │                                                                          │              ║
║  var.flow_logs_s3_bucket_arn │  if "s3":                                                                │              ║
║  var.flow_logs_retention_days├──────────────────► aws_s3_bucket.flow_logs[0] (if no existing bucket)   │              ║
║  var.flow_logs_traffic_type ─┤                    aws_s3_bucket_policy.flow_logs[0]                     │              ║
║  var.flow_logs_kms_key_id ───┤                    aws_flow_log.s3[0]                                    │              ║
║  var.flow_logs_versioning ───┘                                                                          │              ║
║                                                                                                         │              ║
║                                                                                                         ▼              ║
║                                                                                               MODULE OUTPUTS           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_vpc` | 1 | Core VPC resource with CIDR, DNS, and optional IPv6 |
| `aws_internet_gateway` | 1 | Enables internet access for public subnets |
| `aws_subnet` (public) | subnet_count | Public subnets across AZs without automatic public IPv4 assignment |
| `aws_subnet` (private) | subnet_count | Private subnets across AZs without public IP |
| `aws_route_table` (public) | 1 | Shared route table for all public subnets |
| `aws_route_table` (private) | 1 or subnet_count | 1 if nat_gateway_high_availability_enabled=false, N if true |
| `aws_route_table_association` | subnet_count * 2 | Associates subnets with route tables |
| `aws_eip` | 0, 1, or subnet_count | Elastic IPs for NAT Gateways |
| `aws_nat_gateway` | 0, 1, or subnet_count | NAT for private subnet outbound IPv4 |
| `aws_egress_only_internet_gateway` | 0 or 1 | IPv6 egress for private subnets |
| `aws_route` (various) | varies | Routes for IGW, NAT, and EIGW |
| `aws_cloudwatch_log_group` | 0 or 1 | CloudWatch destination for flow logs |
| `aws_iam_role` | 0 or 1 | IAM role for CloudWatch flow logs |
| `aws_s3_bucket` | 0 or 1 | S3 destination for flow logs (if created) |
| `aws_flow_log` | 0 or 1 | VPC Flow Log resource |

## FAQ

### What is the difference between public and private subnets?

| Aspect | Public Subnet | Private Subnet |
|--------|---------------|----------------|
| Public IP | Not auto-assigned by subnet | Not assigned |
| Internet Access | Direct via Internet Gateway | Via NAT Gateway (IPv4) or EIGW (IPv6) |
| Inbound from Internet | Allowed (with security group rules) | Not directly accessible |
| Use Cases | Load balancers, bastion hosts, NAT Gateways | Application servers, databases, internal services |
| Route Table | Routes 0.0.0.0/0 to IGW | Routes 0.0.0.0/0 to NAT Gateway |

**Example Architecture:**

```
Internet
    │
    ▼
┌───────────────────────────────────────────────────┐
│  Public Subnet                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  │
│  │     ALB     │  │   Bastion   │  │ NAT Gateway│  │
│  └──────┬──────┘  └─────────────┘  └─────┬─────┘  │
└─────────┼────────────────────────────────┼────────┘
          │                                │
          ▼                                │
┌─────────────────────────────────────────────────────┐
│  Private Subnet                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   App EC2   │  │   App EC2   │  │   RDS       │  │
│  │   (targets) │  │   (targets) │  │  Database   │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
│                                                      │
│  Outbound to internet: via NAT Gateway ─────────────┘
└─────────────────────────────────────────────────────┘
```

### Which NAT Gateway strategy should I use?

| Strategy | `nat_gateway_high_availability_enabled` | Cost | Availability | Use Case |
|----------|--------------------------------|------|--------------|----------|
| Single NAT | `false` (default) | ~$32/month + data | Single AZ dependency | Dev/staging, cost-sensitive |
| Multi-NAT | `true` | ~$32/month per AZ + data | High availability | Production workloads |

> **Important:** Switching topology between single-NAT and multi-NAT on a live VPC has unavoidable per-subnet egress gaps because AWS only allows one route-table association per subnet at a time. See [Migrating between NAT topologies](#migrating-between-nat-topologies) below for the safe runbook.

**Single NAT Gateway:**
```
┌─────────────────────────────────────────────────────────────────────┐
│  Public Subnets                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │   AZ-1a     │  │   AZ-1b     │  │   AZ-1c     │                 │
│  │ NAT Gateway │  │             │  │             │                 │
│  └──────┬──────┘  └─────────────┘  └─────────────┘                 │
│         │                                                           │
│         └─────────────────────────────────────────────┐             │
│                                                       │             │
└───────────────────────────────────────────────────────┼─────────────┘
                                                        │
┌───────────────────────────────────────────────────────┼─────────────┐
│  Private Subnets (all use single NAT)                 │             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │             │
│  │   AZ-1a     │──│   AZ-1b     │──│   AZ-1c     │───┘             │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                                                     │
│  Risk: If AZ-1a fails, all private subnets lose internet access    │
└─────────────────────────────────────────────────────────────────────┘
```

**Multi-NAT Gateway (High Availability):**
```
┌─────────────────────────────────────────────────────────────────────┐
│  Public Subnets                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │   AZ-1a     │  │   AZ-1b     │  │   AZ-1c     │                 │
│  │ NAT Gateway │  │ NAT Gateway │  │ NAT Gateway │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                         │
└─────────┼────────────────┼────────────────┼─────────────────────────┘
          │                │                │
┌─────────┼────────────────┼────────────────┼─────────────────────────┐
│  Private Subnets (each AZ uses its own NAT)                         │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐                 │
│  │   AZ-1a     │  │   AZ-1b     │  │   AZ-1c     │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                                                     │
│  Benefit: Each AZ is independent, no single point of failure       │
└─────────────────────────────────────────────────────────────────────┘
```

### How does automatic CIDR allocation work?

When you don't specify `public_subnet_cidrs` or `private_subnet_cidrs`, the module automatically calculates them using `cidrsubnet()`:

```
VPC CIDR: 10.0.0.0/16 (65,536 IPs)
                │
                ├── Public Subnets (/24 = 256 IPs each)
                │   ├── cidrsubnet(vpc_cidr, 8, 1)  → 10.0.1.0/24   (AZ-1)
                │   ├── cidrsubnet(vpc_cidr, 8, 2)  → 10.0.2.0/24   (AZ-2)
                │   └── cidrsubnet(vpc_cidr, 8, 3)  → 10.0.3.0/24   (AZ-3)
                │
                └── Private Subnets (/24 = 256 IPs each)
                    ├── cidrsubnet(vpc_cidr, 8, 11) → 10.0.11.0/24  (AZ-1)
                    ├── cidrsubnet(vpc_cidr, 8, 12) → 10.0.12.0/24  (AZ-2)
                    └── cidrsubnet(vpc_cidr, 8, 13) → 10.0.13.0/24  (AZ-3)
```

**Custom CIDR Example:**

For larger subnets or different allocation:

```hcl
module "vpc" {
  source = "..."

  name         = "custom-vpc"
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 3

  # Larger /20 subnets (4,096 IPs each)
  public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}
```

### When should I enable IPv6?

| Scenario | Enable IPv6? | Notes |
|----------|--------------|-------|
| Modern applications with IPv6 requirements | Yes | Full dual-stack support |
| IoT devices or mobile apps | Often | Many carriers use IPv6 |
| Internal-only workloads | Optional | IPv4 sufficient |
| Legacy applications | No | May not support IPv6 |
| Cost optimization | Consider | IPv6 has no NAT Gateway costs |

**IPv6 Architecture:**
```
                          Internet
                              │
                    ┌─────────┴─────────┐
                    │                   │
               IPv4 Route          IPv6 Route
            (0.0.0.0/0 → IGW)    (::/0 → IGW)
                    │                   │
                    ▼                   ▼
            ┌───────────────────────────────┐
            │        Public Subnets          │
            │   IPv4 + IPv6 (dual-stack)     │
            └───────────────────────────────┘
                    │
            ┌───────┴───────┐
            │               │
       IPv4 Route      IPv6 Route
    (0.0.0.0/0 → NAT)  (::/0 → EIGW)
            │               │
            ▼               ▼
            ┌───────────────────────────────┐
            │       Private Subnets          │
            │   IPv4 (NAT) + IPv6 (EIGW)     │
            │   Egress-only for IPv6         │
            └───────────────────────────────┘
```

### How do I choose VPC Flow Logs destination?

| Destination | Cost | Query Capability | Retention | Use Case |
|-------------|------|------------------|-----------|----------|
| CloudWatch Logs | Higher for large volumes | CloudWatch Insights | Configurable (1-3653 days) | Real-time analysis, smaller VPCs |
| S3 | Lower for large volumes | Athena queries | Lifecycle policies | Long-term storage, compliance |

**CloudWatch Flow Logs:**
```hcl
module "vpc" {
  # ...
  flow_logs_enabled        = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 30
  flow_logs_traffic_type   = "REJECT"  # Only rejected traffic for security analysis
}
```

**S3 Flow Logs with KMS encryption:**
```hcl
module "vpc" {
  # ...
  flow_logs_enabled            = true
  flow_logs_destination        = "s3"
  flow_logs_kms_key_id         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  flow_logs_versioning_enabled = true
  flow_logs_retention_days     = 90
}
```

## Migrating between NAT topologies

Switching between single-NAT and multi-NAT (HA) on a **live** VPC needs care: each subnet's route-table association must be replaced (destroy-then-create) because AWS only allows one association per subnet at a time. The window is short (~1 second per subnet), but new connections during that window will fail. Existing connections survive on the previous NAT's connection-tracking until they tear down naturally.

### Pre-flight checklist

Before applying:

1. **Decide the migration window.** Per-subnet egress gap of ~1s on each association swap. New TCP/UDP connections fail during the gap.
2. **Verify the destination route table has the right routes.** When swapping a subnet onto a different RT, that RT must already have a working `0.0.0.0/0 → NAT` (and `::/0 → EIGW` if IPv6) route, or the subnet has zero egress until the route is added.
3. **Check NAT capacity** (single-NAT direction). One NAT GW handles up to ~45 Gbps and 55k connections per dest IP/port pair, scaling automatically. Confirm your aggregate traffic fits.
4. **Match `nat_gateway_eip_allocation_ids` to the target topology.** Length 1 for single-NAT, the resolved `subnet_count` for HA. The module's validation rejects mismatches.
5. **Run `tofu plan` first** and verify there's no `-/+` on `aws_nat_gateway.this[0]` and no changes to `aws_route_table.private[0]`'s NAT route. If either appears, investigate before applying — those signal an unintended replacement.

### HA → Single

```hcl
nat_gateway_high_availability_enabled = false
nat_gateway_eip_allocation_ids = [<eip-0>]
```

Apply in stages so only one AZ's egress is affected at a time:

```bash
# Stage 1: move subnet[1] onto RT[0]. Subnet[2] still routes via NAT[2].
tofu apply -target='aws_route_table_association.private[1]'
# Verify subnet[1] connectivity (curl from a workload).

# Stage 2: move subnet[2] onto RT[0]. Subnet[1] is now stable on NAT[0].
tofu apply -target='aws_route_table_association.private[2]'
# Verify subnet[2] connectivity.

# Stage 3: clean up the now-orphan NATs and RTs (no traffic depends on them).
tofu apply
```

Stages 1 and 2 each have a ~1s egress gap on the moving subnet. Stage 3 is gap-free.

### Single → HA

Inverse direction: spin up new NATs and RTs first (no impact), then swap subnets onto them one at a time.

```hcl
nat_gateway_high_availability_enabled = true
nat_gateway_eip_allocation_ids = [<eip-0>, <eip-1>, <eip-2>]   # length = subnet_count
```

```bash
# Stage 1: create new NATs and RTs. Subnets still routed via RT[0]/NAT[0].
tofu apply \
  -target='aws_nat_gateway.this' \
  -target='aws_route_table.private' \
  -target='aws_route.private_nat'
# All three NATs now exist; new RTs have correct routes; nothing has moved yet.

# Stage 2: swap subnet[1] onto its own RT.
tofu apply -target='aws_route_table_association.private[1]'

# Stage 3: swap subnet[2] onto its own RT.
tofu apply -target='aws_route_table_association.private[2]'

# Stage 4: final converge (tag updates, etc.)
tofu apply
```

### Recovery if an apply fails mid-flight

If a topology-change apply fails partway (e.g. `Resource.AlreadyAssociated` or `EIP already associated`), state and AWS reality are out of sync. **Don't blindly delete resources** — private subnets will lose internet egress and break further deploys. Instead:

1. Identify the orphaned resources in AWS (`describe-nat-gateways`, `describe-route-tables`).
2. Import them back into state at the addresses Terraform expects:
   ```bash
   tofu import 'aws_nat_gateway.this[0]' <nat-id>
   ```
3. `tofu refresh` to reconcile.
4. Re-plan and confirm before re-applying.

## Migrating from `single_nat_gateway` to `nat_gateway_high_availability_enabled`

The variable was renamed (and inverted) in a recent version. The old `single_nat_gateway` is still accepted as a deprecated input; when set, it overrides `nat_gateway_high_availability_enabled`. To migrate:

| Old | New |
|-----|-----|
| `single_nat_gateway = true` (or unset) | `nat_gateway_high_availability_enabled = false` (default) |
| `single_nat_gateway = false` | `nat_gateway_high_availability_enabled = true` |

**You can update the variable name in your config without any topology change** — the resulting plan should be a no-op (or only cosmetic tag updates) as long as you flip the boolean correctly. Workspaces still passing `single_nat_gateway` continue to work; the deprecated variable will be removed in a future major version.

## Notes

- The `name` variable must be between 1 and 36 characters to ensure S3 bucket names for VPC flow logs stay within the 63 character limit
- DNS support and hostnames are enabled by default, which is required for services like RDS, ECS, and EFS
- When using automatic subnet CIDR allocation, public subnets use offsets 1-6 and private subnets use offsets 11-16
- Public subnets route to the Internet Gateway but do not automatically assign public IPv4 addresses to launched instances
- NAT Gateway requires an Internet Gateway to exist first (handled automatically via `depends_on`)
- Elastic IPs for NAT Gateways are allocated with `domain = "vpc"` for VPC usage. To reuse pre-allocated EIPs (e.g. from the `networking/eips` module), set `nat_gateway_eip_allocation_ids`; the module will skip creating internal EIPs.
- The Egress-Only Internet Gateway only routes IPv6 traffic and only allows outbound connections
- VPC Flow Logs have a 60-second aggregation interval for near real-time monitoring
- When using S3 for flow logs with an existing bucket, ensure the bucket policy allows the VPC Flow Logs service principal
- Private route tables: 1 table when `nat_gateway_high_availability_enabled = false`, or 1 per AZ when `true`
- All resources are tagged with `ManagedBy = "terraform"` and `Module = "networking/vpc"` by default
- Subnet preconditions validate that the resolved `subnet_count` doesn't exceed selected or available AZs

## License

This module is part of the Ravion Modules library and is licensed under the Functional Source License, Version 1.1, MIT Future License (FSL-1.1-MIT).
