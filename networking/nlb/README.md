# Network Load Balancer Module

This module creates an AWS Network Load Balancer (NLB) with optional access logging, static IP (Elastic IP) support, cross-zone load balancing, and security group attachments.

## Features

- Network Load Balancer operating at Layer 4 (Transport Layer)
- Support for TCP, UDP, TLS, and TCP_UDP protocols
- Ultra-low latency with millions of requests per second
- Static IP addresses via Elastic IPs for firewall whitelisting
- Cross-zone load balancing for even traffic distribution
- Managed security group with referenceable ID for downstream services
- S3 access logging with automatic bucket creation
- Configurable log retention and KMS encryption
- DNS client routing policy configuration
- PrivateLink traffic security enforcement
- Deletion protection for production safety

## Usage

### Basic NLB

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  tags = {
    Environment = "production"
  }
}

# Service modules create their own listeners and target groups
module "api_service" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  # ... service configuration ...

  load_balancer_attachment = {
    nlb_arn = module.nlb.nlb_arn
    nlb_listener = {
      port     = 443
      protocol = "TLS"
      # ... listener configuration ...
    }
    target_group = {
      port     = 8080
      protocol = "TCP"
    }
  }
}
```

### Internal NLB

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "internal"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  internal_load_balancer_enabled   = true
}
```

### NLB with Static IPs (Elastic IPs)

For scenarios requiring static IP addresses (e.g., firewall rules):

```hcl
resource "aws_eip" "nlb" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "nlb-${count.index + 1}"
  }
}

module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "static-ip"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  elastic_ips_enabled        = true
  elastic_ip_allocation_ids = aws_eip.nlb[*].allocation_id
}
```

### NLB with Access Logs

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "logged"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Access Logs - creates S3 bucket automatically
  access_logs_enabled         = true
  access_logs_retention_days = 365
}
```

### NLB with Existing S3 Bucket for Logs

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "logged"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  access_logs_enabled     = true
  access_logs_bucket_arn = "arn:aws:s3:::my-existing-logs-bucket"
  access_logs_prefix     = "nlb-logs"
}
```

### Cross-Zone Load Balancing

Enable cross-zone load balancing to distribute traffic evenly across all targets:

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "cross-zone"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  cross_zone_load_balancing_enabled = true
}
```

### NLB with Managed Security Group

The module creates a managed security group that can be referenced by downstream services to restrict traffic to only what comes through the NLB:

```hcl
module "nlb" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/nlb?ref=v1.0.0"

  name       = "secured"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Define which ports the NLB will expose
  listener_ports = [
    { port = 443, protocol = "tls" },
    { port = 80, protocol = "tcp" },
  ]

  # Restrict ingress to specific CIDRs (defaults to 0.0.0.0/0)
  ingress_cidr_blocks = ["10.0.0.0/8"]
}

# Reference the NLB security group in target service security groups
resource "aws_vpc_security_group_ingress_rule" "from_nlb" {
  security_group_id            = module.service.security_group_id
  referenced_security_group_id = module.nlb.security_group_id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "Allow traffic from NLB"
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
| name | Name prefix for all resources created by this module | `string` | n/a | yes |
| vpc_id | The ID of the VPC where the NLB will be created | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the NLB (use public subnets for internet-facing) | `list(string)` | n/a | yes |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |

### NLB Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| internal_load_balancer_enabled | If true, the NLB will be internal (not internet-facing) | `bool` | `false` | no |
| deletion_protection_enabled | If true, the resource cannot be deleted via the AWS API until this is set to false | `bool` | `true` | no |
| cross_zone_load_balancing_enabled | Enable cross-zone load balancing | `bool` | `false` | no |
| dns_record_client_routing_policy | How traffic is distributed among NLB AZs (any_availability_zone, availability_zone_affinity, partial_availability_zone_affinity) | `string` | `null` | no |

### Security Group

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| listener_ports | List of port/protocol pairs to allow in the NLB security group | `list(object({ port = number, protocol = string }))` | `[]` | no |
| ingress_cidr_blocks | IPv4 CIDR blocks allowed to access the NLB | `list(string)` | `["0.0.0.0/0"]` | no |
| ingress_ipv6_cidr_blocks | IPv6 CIDR blocks allowed to access the NLB | `list(string)` | `["::/0"]` | no |
| additional_security_group_ids | Additional security group IDs to attach alongside the managed one | `list(string)` | `[]` | no |
| enforce_security_group_inbound_rules_on_private_link_traffic | Whether inbound SG rules are enforced for PrivateLink traffic (on/off) | `string` | `null` | no |

### Elastic IPs (Static IPs)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| elastic_ips_enabled | Enable static IP addresses using Elastic IPs | `bool` | `false` | no |
| elastic_ip_allocation_ids | A list of Elastic IP allocation IDs, one per subnet | `list(string)` | `[]` | no |

### Access Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| access_logs_enabled | Enable access logging for the NLB | `bool` | `false` | no |
| access_logs_bucket_arn | ARN of an existing S3 bucket for access logs (creates new if null) | `string` | `null` | no |
| access_logs_prefix | The S3 prefix for access logs | `string` | `""` | no |
| access_logs_retention_days | Days to retain access logs in S3 | `number` | `90` | no |
| access_logs_kms_key_id | KMS key ID for S3 bucket encryption (uses AES256 if null) | `string` | `null` | no |
| access_logs_versioning_enabled | Enable versioning for the access logs S3 bucket | `bool` | `false` | no |

## Outputs

### Network Load Balancer

| Name | Description |
|------|-------------|
| nlb_id | The ID of the Network Load Balancer |
| nlb_arn | The ARN of the Network Load Balancer |
| nlb_arn_suffix | The ARN suffix of the NLB for use with CloudWatch Metrics |
| nlb_dns_name | The DNS name of the Network Load Balancer |
| nlb_zone_id | The canonical hosted zone ID of the NLB (for Route53 alias records) |

### Security Group

| Name | Description |
|------|-------------|
| security_group_id | The ID of the NLB security group |
| security_group_arn | The ARN of the NLB security group |

### Access Logs

| Name | Description |
|------|-------------|
| access_logs_bucket_name | The name of the S3 bucket for access logs (null if disabled or using existing bucket) |
| access_logs_bucket_arn | The ARN of the S3 bucket for access logs (null if disabled or using existing bucket) |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         Network Load Balancer                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        NLB (Layer 4)                                    │  │
│  │  • TCP/UDP/TLS/TCP_UDP protocols                                       │  │
│  │  • Ultra-low latency (microseconds)                                    │  │
│  │  • Millions of requests per second                                     │  │
│  │  • Preserves client source IP                                          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│         ┌───────────────────────────┼───────────────────────────┐            │
│         ▼                           ▼                           ▼            │
│  ┌──────────────┐          ┌──────────────┐          ┌──────────────┐       │
│  │ Elastic IPs  │          │   Security   │          │  Access Logs │       │
│  │ (optional)   │          │   Groups     │          │  S3 Bucket   │       │
│  │              │          │  (optional)  │          │  (optional)  │       │
│  └──────────────┘          └──────────────┘          └──────────────┘       │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                       Cross-Zone Load Balancing                         │  │
│  │  • Distributes traffic evenly across all AZs                           │  │
│  │  • Optional (disabled by default due to cross-AZ data transfer costs)  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                         NETWORKING/NLB TERRAFORM MODULE                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │      NETWORK                    │   │      NLB SETTINGS                       │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • vpc_id (required)             │   │ • internal_load_balancer_enabled                              │  ║
║  │ • tags                      │   │ • subnet_ids (required)         │   │ • deletion_protection_enabled                   │  ║
║  └──────────────┬──────────────┘   │ • security_group_ids            │   │ • cross_zone_load_balancing_enabled      │  ║
║                 │                  └─────────────────────────────────┘   │ • dns_record_client_routing_policy      │  ║
║                 │                                                        │ • enforce_security_group_inbound_rules  │  ║
║                 │                                                        │   _on_private_link_traffic              │  ║
║                 │                                                        └─────────────────────────────────────────┘  ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "networking/nlb" }                                  │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                   │   │  ║
║  │  │                                                                                                           │   │  ║
║  │  │ ACCESS LOGS FLAGS:                                                                                        │   │  ║
║  │  │ • create_access_logs_bucket = var.access_logs_enabled && var.access_logs_bucket_arn == null               │   │  ║
║  │  │ • access_logs_bucket_name = create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id :                │   │  ║
║  │  │                             (var.access_logs_bucket_arn != null ? regex(...) : null)                     │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │    ELASTIC IPs              │   │      ACCESS LOGS                │   │      ACCESS LOGS S3 CONFIG              │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • elastic_ips_enabled        │   │ • access_logs_enabled            │   │ • access_logs_retention_days            │  ║
║  │ • elastic_ip_allocation_ids │   │ • access_logs_bucket_arn        │   │ • access_logs_kms_key_id                │  ║
║  └─────────────────────────────┘   │ • access_logs_prefix            │   │ • access_logs_versioning_enabled        │  ║
║                                    └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                   DATA SOURCES                                                               │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ • data.aws_caller_identity.current   - Gets AWS account ID for S3 bucket naming                             │    ║
║    │ • data.aws_region.current            - Gets current region for S3 bucket naming                             │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                         aws_lb.this                                                          │    ║
║    │                                        (CORE RESOURCE)                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  load_balancer_type = "network"                                                                             │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────┐   ┌─────────────────────┐   ┌───────────────────────┐                                  │    ║
║    │  │ subnet_mapping  │   │    access_logs      │   │   lifecycle           │                                  │    ║
║    │  │   (dynamic)     │   │     (dynamic)       │   │   precondition        │                                  │    ║
║    │  │                 │   │                     │   │   (EIP validation)    │                                  │    ║
║    │  │ Maps subnet_ids │   │ Configures S3       │   │                       │                                  │    ║
║    │  │ to EIP alloc    │   │ bucket and prefix   │   │ Validates EIP count   │                                  │    ║
║    │  │ IDs when EIPs   │   │ when enabled        │   │ matches subnet count  │                                  │    ║
║    │  │ are enabled     │   │                     │   │                       │                                  │    ║
║    │  └─────────────────┘   └─────────────────────┘   └───────────────────────┘                                  │    ║
║    │                                                                                                              │    ║
║    │  depends_on = [aws_s3_bucket_policy.access_logs]                                                            │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                   ┌───────────────────────────────────────┴───────────────────────────────────────┐                    ║
║                   │                                                                               │                    ║
║                   ▼                                                                               ▼                    ║
║    ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║    │                                     ACCESS LOGS S3 RESOURCES                                                  │   ║
║    │                              (conditional: create_access_logs_bucket = true)                                  │   ║
║    ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║    │                                                                                                               │   ║
║    │  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌────────────────────────────────┐  │   ║
║    │  │ aws_s3_bucket.access_logs   │   │ aws_s3_bucket_public_access     │   │ aws_s3_bucket_server_side      │  │   ║
║    │  │                             │   │ _block.access_logs              │   │ _encryption_configuration      │  │   ║
║    │  ├─────────────────────────────┤   ├─────────────────────────────────┤   │ .access_logs                   │  │   ║
║    │  │ • Bucket for NLB logs       │   │ • block_public_acls = true      │   ├────────────────────────────────┤  │   ║
║    │  │ • Unique naming with        │   │ • block_public_policy = true    │   │ • AES256 or aws:kms            │  │   ║
║    │  │   account ID and region     │   │ • ignore_public_acls = true     │   │ • Optional KMS key             │  │   ║
║    │  │ • force_destroy = true      │   │ • restrict_public_buckets = true│   │                                │  │   ║
║    │  └─────────────────────────────┘   └─────────────────────────────────┘   └────────────────────────────────┘  │   ║
║    │                                                                                                               │   ║
║    │  ┌─────────────────────────────┐   ┌─────────────────────────────────┐                                       │   ║
║    │  │ aws_s3_bucket_versioning    │   │ aws_s3_bucket_lifecycle         │                                       │   ║
║    │  │ .access_logs                │   │ _configuration.access_logs      │                                       │   ║
║    │  ├─────────────────────────────┤   ├─────────────────────────────────┤                                       │   ║
║    │  │ • Enabled/Disabled based    │   │ • Automatic log expiration      │                                       │   ║
║    │  │   on variable               │   │ • Retention days configurable   │                                       │   ║
║    │  └─────────────────────────────┘   └─────────────────────────────────┘                                       │   ║
║    │                                                                                                               │   ║
║    │  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │   ║
║    │  │ aws_s3_bucket_policy.access_logs                                                                        │ │   ║
║    │  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤ │   ║
║    │  │ • AllowNLBLogDelivery: Allows delivery.logs.amazonaws.com to PutObject                                 │ │   ║
║    │  │ • AllowNLBLogDeliveryAclCheck: Allows delivery.logs.amazonaws.com to GetBucketAcl                      │ │   ║
║    │  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │   ║
║    └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │       NETWORK LOAD BALANCER             │   │           ACCESS LOGS                   │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • nlb_id                                │   │ • access_logs_bucket_name               │                            ║
║  │ • nlb_arn                               │   │ • access_logs_bucket_arn                │                            ║
║  │ • nlb_arn_suffix                        │   └─────────────────────────────────────────┘                            ║
║  │ • nlb_dns_name                          │                                                                          ║
║  │ • nlb_zone_id                           │                                                                          ║
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
║                                        │      var.name           │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║  var.vpc_id ─────────────────────────────► aws_lb.this (NLB)                                                          ║
║  var.subnet_ids ─────────────────────────►      │                                                                     ║
║  var.internal_load_balancer_enabled ───────────────────────────►      │                                                                     ║
║  var.security_group_ids ─────────────────►      │                                                                     ║
║  var.deletion_protection_enabled ────────────────►      │                                                                     ║
║  var.cross_zone_load_balancing_enabled ───►      │                                                                     ║
║  var.dns_record_client_routing_policy ───►      │                                                                     ║
║  local.tags ─────────────────────────────►      │                                                                     ║
║                                                  │                                                                     ║
║  var.elastic_ips_enabled ─────────────────►      │ (dynamic subnet_mapping)                                            ║
║  var.elastic_ip_allocation_ids ──────────►      │                                                                     ║
║                                                  │                                                                     ║
║  var.access_logs_enabled ─────────────────►      │ (dynamic access_logs)                                               ║
║  local.access_logs_bucket_name ──────────►      │                                                                     ║
║  var.access_logs_prefix ─────────────────►      │                                                                     ║
║                                                  │                                                                     ║
║                                                  ▼                                                                     ║
║           ┌──────────────────────────────────────┴────────────────────────────────────────┐                            ║
║           │                                                                               │                            ║
║           ▼                                                                               ▼                            ║
║  ┌────────────────────────────────────────────┐                      ┌────────────────────────────────────────────┐   ║
║  │          NLB OUTPUTS                       │                      │     ACCESS LOGS S3 RESOURCES               │   ║
║  ├────────────────────────────────────────────┤                      │  (when create_access_logs_bucket = true)   │   ║
║  │ • nlb_id = aws_lb.this.id                  │                      ├────────────────────────────────────────────┤   ║
║  │ • nlb_arn = aws_lb.this.arn                │                      │                                            │   ║
║  │ • nlb_arn_suffix = aws_lb.this.arn_suffix  │                      │  var.access_logs_retention_days ─────────► │   ║
║  │ • nlb_dns_name = aws_lb.this.dns_name      │                      │  var.access_logs_kms_key_id ─────────────► │   ║
║  │ • nlb_zone_id = aws_lb.this.zone_id        │                      │  var.access_logs_versioning_enabled ─────► │   ║
║  └────────────────────────────────────────────┘                      │                                            │   ║
║                                                                      │  ┌────────────────────────────────────┐    │   ║
║                                                                      │  │ aws_s3_bucket.access_logs          │    │   ║
║                                                                      │  │ aws_s3_bucket_public_access_block  │    │   ║
║                                                                      │  │ aws_s3_bucket_server_side_enc...   │    │   ║
║                                                                      │  │ aws_s3_bucket_versioning           │    │   ║
║                                                                      │  │ aws_s3_bucket_lifecycle_config...  │    │   ║
║                                                                      │  │ aws_s3_bucket_policy               │    │   ║
║                                                                      │  └──────────────┬─────────────────────┘    │   ║
║                                                                      └─────────────────┼──────────────────────────┘   ║
║                                                                                        │                              ║
║                                                                                        ▼                              ║
║                                                                      ┌────────────────────────────────────────────┐   ║
║                                                                      │     ACCESS LOGS OUTPUTS                    │   ║
║                                                                      ├────────────────────────────────────────────┤   ║
║                                                                      │ • access_logs_bucket_name                  │   ║
║                                                                      │ • access_logs_bucket_arn                   │   ║
║                                                                      └────────────────────────────────────────────┘   ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_lb` | 1 | Core Network Load Balancer resource |
| `aws_s3_bucket` | 0 or 1 | Access logs storage bucket |
| `aws_s3_bucket_public_access_block` | 0 or 1 | Block public access to logs bucket |
| `aws_s3_bucket_server_side_encryption_configuration` | 0 or 1 | Encrypt logs bucket (AES256 or KMS) |
| `aws_s3_bucket_versioning` | 0 or 1 | Optional versioning for logs |
| `aws_s3_bucket_lifecycle_configuration` | 0 or 1 | Automatic log retention/expiration |
| `aws_s3_bucket_policy` | 0 or 1 | Allow NLB to write access logs |

## FAQ

### When should I use NLB vs ALB?

| Use Case | Recommended | Reason |
|----------|-------------|--------|
| HTTP/HTTPS web applications | ALB | Layer 7 routing, path/host-based routing, WAF support |
| TCP/UDP services (databases, gaming, IoT) | NLB | Layer 4, ultra-low latency, preserves client IP |
| gRPC services | Both | ALB for HTTP/2 features, NLB for raw TCP performance |
| Static IP requirements | NLB | Supports Elastic IPs for firewall whitelisting |
| Millions of requests/second | NLB | Designed for extreme throughput with microsecond latencies |
| WebSocket connections | Both | ALB native support, NLB via TCP |
| TLS passthrough | NLB | Pass-through TLS to backend for end-to-end encryption |

### Why is cross-zone load balancing disabled by default?

Cross-zone load balancing distributes traffic evenly across all targets in all enabled Availability Zones, regardless of which AZ receives the request. While this provides more even distribution:

1. **Cost**: AWS charges for cross-zone data transfer
2. **Latency**: Cross-AZ traffic adds ~1-2ms latency
3. **When to enable**:
   - Uneven target distribution across AZs
   - Consistent capacity requirements per-AZ
   - When even distribution is more important than cost/latency

```hcl
# Enable when you have uneven target distribution
cross_zone_load_balancing_enabled = true
```

### How do Elastic IPs work with NLB?

Elastic IPs provide static IP addresses for your NLB, useful when clients need to whitelist specific IPs:

```
┌─────────────────────────────────────────────────────────────────┐
│                    NLB with Elastic IPs                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  AZ-a                    AZ-b                    AZ-c           │
│  ┌──────────────┐       ┌──────────────┐       ┌──────────────┐ │
│  │ EIP: 1.2.3.4 │       │ EIP: 5.6.7.8 │       │ EIP: 9.10.   │ │
│  │              │       │              │       │ 11.12        │ │
│  │ subnet-aaa   │       │ subnet-bbb   │       │ subnet-ccc   │ │
│  └──────────────┘       └──────────────┘       └──────────────┘ │
│                                                                  │
│  Clients whitelist: 1.2.3.4, 5.6.7.8, 9.10.11.12               │
└─────────────────────────────────────────────────────────────────┘
```

**Requirements:**
- One EIP per subnet (same count)
- Only supported for internet-facing NLBs
- EIPs must be created before the NLB

### How does NLB preserve client IP addresses?

NLB preserves the original client IP address by default:

| Target Type | Client IP Preserved? | Notes |
|-------------|---------------------|-------|
| Instance | Yes | Client IP in packet source |
| IP | Yes | Client IP in packet source |
| ALB | No | ALB IP is the source (use X-Forwarded-For) |

For TLS listeners with proxy protocol disabled, enable proxy protocol v2 on the target group to preserve client IP.

### Why does this module only create the NLB (not listeners/target groups)?

This module follows the principle of separation of concerns:

```
┌─────────────────────────────────────────┐
│             NLB Module                  │
│  (networking/nlb)                       │
│  • Creates NLB infrastructure           │
│  • Manages access logs                  │
│  • Configures Elastic IPs               │
│  • Outputs: nlb_arn, nlb_dns_name       │
└─────────────────────────────────────────┘
              │
              │ nlb_arn
              ▼
┌─────────────────────────────────────────┐
│         Service Module                  │
│  (compute/ecs_service, etc.)            │
│  • Creates listeners                    │
│  • Creates target groups                │
│  • Registers targets                    │
│  • Manages health checks                │
└─────────────────────────────────────────┘
```

**Benefits:**
- Services manage their own listener/target group lifecycle
- Multiple services can share one NLB
- Service-specific configuration stays with the service
- Independent service deployments

### What DNS routing policies are available?

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `any_availability_zone` | Route to any healthy AZ | Default behavior, maximizes availability |
| `availability_zone_affinity` | Prefer client's AZ | Reduce latency, minimize cross-AZ traffic |
| `partial_availability_zone_affinity` | Partial AZ preference | Balance between availability and affinity |

## Security Considerations

- **Managed Security Group**: The module creates a security group that is automatically attached to the NLB. Use `listener_ports` to define which ports are allowed. Reference `security_group_id` in downstream service security groups to restrict traffic to NLB-only sources.
- **Client IP Preservation**: NLB preserves the client's source IP by default (for non-TLS targets).
- **Access Logs**: Enable access logging for audit trails, troubleshooting, and compliance.
- **PrivateLink**: Use `enforce_security_group_inbound_rules_on_private_link_traffic` to control traffic from PrivateLink endpoints.
- **Encryption**: When creating an access logs bucket, encryption is enabled by default (AES256 or KMS).

## ALB vs NLB Comparison

| Feature            | ALB                  | NLB                               |
| ------------------ | -------------------- | --------------------------------- |
| OSI Layer          | Layer 7 (HTTP/HTTPS) | Layer 4 (TCP/UDP/TLS)             |
| Protocols          | HTTP, HTTPS          | TCP, UDP, TLS, TCP_UDP            |
| Latency            | Low (~ms)            | Ultra-low (~us)                   |
| Static IPs         | No                   | Yes (via Elastic IPs)             |
| Security Groups    | Yes (managed)        | Yes (managed)                     |
| Path-based routing | Yes                  | No                                |
| Host-based routing | Yes                  | No                                |
| WebSocket          | Yes                  | Yes (TCP)                         |
| WAF Integration    | Yes                  | No                                |
| Use Case           | Web applications     | High-performance TCP/UDP services |

## Notes

- At least 1 subnet is required (2+ recommended for high availability).
- Cross-zone load balancing is disabled by default (AWS charges for cross-zone data transfer).
- Static IPs via Elastic IPs are only supported for internet-facing NLBs.
- Target groups and listeners are created by service modules that reference this NLB via `nlb_arn`.
- When using an existing S3 bucket for access logs, ensure it has the proper bucket policy for NLB log delivery.
- The access logs S3 bucket name includes the AWS account ID and region to ensure uniqueness.
- Access logs bucket has `force_destroy = true` - be aware this will delete all logs when the module is destroyed.
- Deletion protection is disabled by default; enable it for production NLBs.
- The managed security group is always created and attached. Use `listener_ports` to define ingress rules and `security_group_id` output to reference it in downstream services.
