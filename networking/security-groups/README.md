# AWS Security Groups Module

This module creates an AWS Security Group with configurable ingress and egress rules using the modern `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources.

This module can be used both standalone (called directly by users) and internally by other modules in this library.

## Features

- **Flexible Rules**: Support for multiple ingress and egress rules with different source/destination types
- **Multiple Source Types**: CIDR blocks (IPv4/IPv6), security group references, prefix lists, and self-referencing
- **Modern Resources**: Uses `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` for better state management
- **Lifecycle Management**: `create_before_destroy` for zero-downtime updates
- **Consistent Tagging**: Automatic ManagedBy and Module tags
- **Input Validation**: Comprehensive validation for ports, protocols, CIDR blocks, and source types

## Usage

### Basic Security Group with All Egress

```hcl
module "security_group" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-app"
  name_suffix = "web"
  description = "Security group for web servers"
  vpc_id      = "vpc-12345678"

  all_egress_enabled = true

  ingress_rules = [
    {
      description = "Allow HTTP from anywhere"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    {
      description = "Allow HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Database Security Group with Restricted Egress

```hcl
module "database_sg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-db"
  name_suffix = "postgres"
  description = "Security group for PostgreSQL database"
  vpc_id      = "vpc-12345678"

  ingress_rules = [
    {
      description                  = "Allow PostgreSQL from app servers"
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app12345"
    },
    {
      description = "Allow PostgreSQL from VPC"
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  # Restrict egress to VPC only
  egress_rules = [
    {
      description = "Allow outbound to VPC"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Cache Security Group (ElastiCache Pattern)

```hcl
module "cache_sg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-cache"
  name_suffix = "elasticache"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = "vpc-12345678"

  ingress_rules = [
    {
      description                  = "Allow Redis from app-1"
      from_port                    = 6379
      to_port                      = 6379
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app1"
    },
    {
      description                  = "Allow Redis from app-2"
      from_port                    = 6379
      to_port                      = 6379
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app2"
    },
    {
      description = "Allow Redis from VPC"
      from_port   = 6379
      to_port     = 6379
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  egress_rules = [
    {
      description = "Allow outbound to VPC"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Load Balancer Security Group (ALB Pattern)

```hcl
module "alb_sg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "main"
  name_suffix = "alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = "vpc-12345678"

  all_egress_enabled = true

  ingress_rules = [
    # HTTP from anywhere (IPv4)
    {
      description = "Allow HTTP"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    # HTTP from anywhere (IPv6)
    {
      description = "Allow HTTP IPv6"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv6   = "::/0"
    },
    # HTTPS from anywhere (IPv4)
    {
      description = "Allow HTTPS"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    # HTTPS from anywhere (IPv6)
    {
      description = "Allow HTTPS IPv6"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv6   = "::/0"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Self-Referencing Security Group (Cluster Pattern)

```hcl
module "cluster_sg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-cluster"
  name_suffix = "internal"
  description = "Security group for cluster internal communication"
  vpc_id      = "vpc-12345678"

  all_egress_enabled = true

  ingress_rules = [
    {
      description = "Allow all traffic from cluster members"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      self        = true
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### ECS Service Security Group

```hcl
module "ecs_service_sg" {
  source = "git::https://github.com/ravionhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-service"
  name_suffix = "ecs-service"
  description = "Security group for ECS service"
  vpc_id      = "vpc-12345678"

  all_egress_enabled = true

  ingress_rules = [
    {
      description                  = "Allow traffic from ALB"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.security_group_id
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for the security group | `string` | n/a | yes |
| name_suffix | Suffix to append to the security group name | `string` | `"sg"` | no |
| description | Description of the security group | `string` | `"Managed by Terraform"` | no |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |

### Network

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_id | The ID of the VPC where the security group will be created | `string` | n/a | yes |

### Ingress Rules

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ingress_rules | List of ingress rules with port range, protocol, and source | `list(object)` | `[]` | no |

### Egress Rules

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| egress_rules | List of egress rules with port range, protocol, and destination | `list(object)` | `[]` | no |
| all_egress_enabled | Create default egress rules allowing all outbound traffic | `bool` | `false` | no |
| ipv4_only_egress_enabled | Only create IPv4 egress rule when all_egress_enabled is true | `bool` | `false` | no |

### Rule Object Attributes

| Attribute | Description | Type | Required |
|-----------|-------------|------|----------|
| from_port | Start of port range (0 for all ports with protocol -1) | `number` | yes |
| to_port | End of port range (0 for all ports with protocol -1) | `number` | yes |
| ip_protocol | Protocol: tcp, udp, icmp, icmpv6, or -1 for all | `string` | no (default: tcp) |
| description | Rule description | `string` | no |
| cidr_ipv4 | IPv4 CIDR block | `string` | One source/dest required |
| cidr_ipv6 | IPv6 CIDR block | `string` | One source/dest required |
| referenced_security_group_id | Security group ID | `string` | One source/dest required |
| prefix_list_id | Managed prefix list ID | `string` | One source/dest required |
| self | Reference this security group | `bool` | One source/dest required |

## Outputs

### Security Group

| Name | Description |
|------|-------------|
| security_group_id | The ID of the security group |
| security_group_arn | The ARN of the security group |
| security_group_name | The name of the security group |
| security_group_vpc_id | The VPC ID of the security group |
| security_group_owner_id | The owner ID (AWS account ID) of the security group |

### Ingress Rules

| Name | Description |
|------|-------------|
| ingress_rule_ids | Map of ingress rule keys to their IDs |
| ingress_rule_arns | Map of ingress rule keys to their ARNs |

### Egress Rules

| Name | Description |
|------|-------------|
| egress_rule_ids | Map of egress rule keys to their IDs |
| egress_rule_arns | Map of egress rule keys to their ARNs |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Security Group                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                    aws_security_group.this                             │  │
│  │  • Name: {name}-{name_suffix}                                          │  │
│  │  • VPC association                                                     │  │
│  │  • create_before_destroy lifecycle                                     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│         ┌───────────────────────────┼───────────────────────────┐            │
│         ▼                                                       ▼            │
│  ┌──────────────────────────────┐          ┌──────────────────────────────┐  │
│  │       Ingress Rules          │          │        Egress Rules          │  │
│  ├──────────────────────────────┤          ├──────────────────────────────┤  │
│  │ • CIDR IPv4 sources          │          │ • CIDR IPv4 destinations     │  │
│  │ • CIDR IPv6 sources          │          │ • CIDR IPv6 destinations     │  │
│  │ • Security group references  │          │ • Security group references  │  │
│  │ • Prefix list references     │          │ • Prefix list references     │  │
│  │ • Self-referencing           │          │ • Self-referencing           │  │
│  └──────────────────────────────┘          │ • Allow-all defaults         │  │
│                                            └──────────────────────────────┘  │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    NETWORKING/SECURITY-GROUPS TERRAFORM MODULE                                       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │         NETWORK                 │   │       DEFAULT EGRESS                    │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • vpc_id (required)             │   │ • all_egress_enabled                      │  ║
║  │ • name_suffix               │   │                                 │   │ • ipv4_only_egress_enabled            │  ║
║  │ • description               │   │                                 │   │                                         │  ║
║  │ • tags                      │   │                                 │   │                                         │  ║
║  └──────────────┬──────────────┘   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║                 │                                                                                                      ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "networking/security-groups" }                      │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │ • security_group_name = "${var.name}-${var.name_suffix}"                                                  │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ RULE TRANSFORMATIONS:                                                                                      │   │  ║
║  │  │ • ingress_rules_map = { for idx, rule in var.ingress_rules : tostring(idx) => rule }                      │   │  ║
║  │  │ • egress_rules_map = { for idx, rule in var.egress_rules : tostring(idx) => rule }                        │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                         INGRESS RULES                                                            │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • ingress_rules[]:                                                                                               │  ║
║  │   - description                       - from_port, to_port, ip_protocol                                          │  ║
║  │   - cidr_ipv4                         - cidr_ipv6                                                                │  ║
║  │   - referenced_security_group_id      - prefix_list_id                                                           │  ║
║  │   - self (bool)                                                                                                  │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                          EGRESS RULES                                                            │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • egress_rules[]:                                                                                                │  ║
║  │   - description                       - from_port, to_port, ip_protocol                                          │  ║
║  │   - cidr_ipv4                         - cidr_ipv6                                                                │  ║
║  │   - referenced_security_group_id      - prefix_list_id                                                           │  ║
║  │   - self (bool)                                                                                                  │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    aws_security_group.this                                                   │    ║
║    │                                        (CORE RESOURCE)                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  • name = local.security_group_name                                                                          │    ║
║    │  • description = var.description                                                                             │    ║
║    │  • vpc_id = var.vpc_id                                                                                       │    ║
║    │  • tags = merge(local.tags, { Name = local.security_group_name })                                            │    ║
║    │                                                                                                              │    ║
║    │  lifecycle { create_before_destroy = true }                                                                  │    ║
║    └──────────────────────────────────────────────────────────┬──────────────────────────────────────────────────┘    ║
║                                                               │                                                        ║
║                   ┌───────────────────────────────────────────┴───────────────────────────────────────┐                ║
║                   │                                                                                   │                ║
║                   ▼                                                                                   ▼                ║
║    ┌──────────────────────────────────────────────┐    ┌──────────────────────────────────────────────┐              ║
║    │ aws_vpc_security_group_ingress_rule.this     │    │  aws_vpc_security_group_egress_rule.this     │              ║
║    │              (for_each)                      │    │               (for_each)                     │              ║
║    ├──────────────────────────────────────────────┤    ├──────────────────────────────────────────────┤              ║
║    │ • security_group_id                          │    │ • security_group_id                          │              ║
║    │ • from_port, to_port, ip_protocol            │    │ • from_port, to_port, ip_protocol            │              ║
║    │ • cidr_ipv4 / cidr_ipv6                      │    │ • cidr_ipv4 / cidr_ipv6                      │              ║
║    │ • referenced_security_group_id               │    │ • referenced_security_group_id               │              ║
║    │ • prefix_list_id                             │    │ • prefix_list_id                             │              ║
║    │ • self -> uses own security_group_id         │    │ • self -> uses own security_group_id         │              ║
║    └──────────────────────────────────────────────┘    └──────────────────────────────────────────────┘              ║
║                                                                                                                        ║
║                   ┌───────────────────────────────────────────────────────────────────┐                                ║
║                   │                    DEFAULT EGRESS RULES                           │                                ║
║                   │              (conditional: all_egress_enabled = true)               │                                ║
║                   └───────────────────────────────────────────────────────────────────┘                                ║
║                                                               │                                                        ║
║                   ┌───────────────────────────────────────────┴───────────────────────────────────────┐                ║
║                   │                                                                                   │                ║
║                   ▼                                                                                   ▼                ║
║    ┌──────────────────────────────────────────────┐    ┌──────────────────────────────────────────────┐              ║
║    │ aws_vpc_security_group_egress_rule           │    │ aws_vpc_security_group_egress_rule           │              ║
║    │         .allow_all_ipv4[0]                   │    │         .allow_all_ipv6[0]                   │              ║
║    │        (count: 0 or 1)                       │    │  (count: 0 or 1, based on ipv4_only)         │              ║
║    ├──────────────────────────────────────────────┤    ├──────────────────────────────────────────────┤              ║
║    │ • ip_protocol = "-1"                         │    │ • ip_protocol = "-1"                         │              ║
║    │ • cidr_ipv4 = "0.0.0.0/0"                    │    │ • cidr_ipv6 = "::/0"                         │              ║
║    │ • All outbound IPv4 traffic                  │    │ • All outbound IPv6 traffic                  │              ║
║    └──────────────────────────────────────────────┘    └──────────────────────────────────────────────┘              ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         SECURITY GROUP                  │   │           INGRESS RULES                 │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • security_group_id                     │   │ • ingress_rule_ids (map)                │                            ║
║  │ • security_group_arn                    │   │ • ingress_rule_arns (map)               │                            ║
║  │ • security_group_name                   │   └─────────────────────────────────────────┘                            ║
║  │ • security_group_vpc_id                 │                                                                          ║
║  │ • security_group_owner_id               │   ┌─────────────────────────────────────────┐                            ║
║  └─────────────────────────────────────────┘   │           EGRESS RULES                  │                            ║
║                                                ├─────────────────────────────────────────┤                            ║
║                                                │ • egress_rule_ids (map)                 │                            ║
║                                                │ • egress_rule_arns (map)                │                            ║
║                                                └─────────────────────────────────────────┘                            ║
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
║                                        │    var.name_suffix      │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║                                        ┌─────────────────────────┐                                                     ║
║                                        │ local.security_group    │                                                     ║
║                                        │         _name           │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║  var.description ───────────────────────────────────┼──────────────────────────────────────┐                           ║
║  var.vpc_id ────────────────────────────────────────┼──────────────────────────────────────┤                           ║
║  local.tags ────────────────────────────────────────┼──────────────────────────────────────┤                           ║
║                                                     │                                      │                           ║
║                                                     ▼                                      ▼                           ║
║                              ┌───────────────────────────────────────────────────────────────┐                         ║
║                              │                                                               │                         ║
║                              │              aws_security_group.this                          │                         ║
║                              │                                                               │                         ║
║                              └────────────────────────────┬──────────────────────────────────┘                         ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐            ║
║           │                                               │                                               │            ║
║           ▼                                               │                                               ▼            ║
║  var.ingress_rules                                        │                                      var.egress_rules      ║
║           │                                               │                                               │            ║
║           ▼                                               │                                               ▼            ║
║  local.ingress_rules_map                                  │                                      local.egress_rules    ║
║           │                                               │                                      _map    │            ║
║           ▼                                               │                                               ▼            ║
║  aws_vpc_security_group                                   │                                      aws_vpc_security      ║
║  _ingress_rule.this                                       │                                      _group_egress_rule    ║
║  (for_each)                                               │                                      .this (for_each)      ║
║           │                                               │                                               │            ║
║           │                                               │                                               │            ║
║           │                              var.all_egress_enabled                                             │            ║
║           │                              var.ipv4_only_egress_enabled                                   │            ║
║           │                                               │                                               │            ║
║           │                                               ▼                                               │            ║
║           │                              ┌────────────────────────────────┐                               │            ║
║           │                              │ aws_vpc_security_group_egress  │                               │            ║
║           │                              │ _rule.allow_all_ipv4[0]        │                               │            ║
║           │                              │ _rule.allow_all_ipv6[0]        │                               │            ║
║           │                              └────────────────────────────────┘                               │            ║
║           │                                               │                                               │            ║
║           └───────────────────────────────────────────────┴───────────────────────────────────────────────┘            ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║                                                    MODULE OUTPUTS                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_security_group` | 1 | Core security group resource |
| `aws_vpc_security_group_ingress_rule` | for_each | Individual ingress rules |
| `aws_vpc_security_group_egress_rule` | for_each | Individual egress rules |
| `aws_vpc_security_group_egress_rule.allow_all_ipv4` | 0 or 1 | Default allow-all IPv4 egress |
| `aws_vpc_security_group_egress_rule.allow_all_ipv6` | 0 or 1 | Default allow-all IPv6 egress |

## FAQ

### What is the difference between ingress and egress rules?

**Ingress rules** control **inbound** traffic - traffic coming INTO your resources from external sources.

**Egress rules** control **outbound** traffic - traffic going OUT from your resources to external destinations.

```
                    ┌─────────────────────────────────────┐
                    │         Your EC2 Instance           │
                    │         (Security Group)            │
                    └─────────────────────────────────────┘
                              ▲                │
                              │                │
                    INGRESS   │                │   EGRESS
                    (Inbound) │                │  (Outbound)
                              │                ▼
                    ┌─────────────────────────────────────┐
                    │           External World            │
                    │    (Internet, Other VPCs, etc.)     │
                    └─────────────────────────────────────┘
```

**Example Use Cases:**

| Direction | Example Rule | Purpose |
|-----------|-------------|---------|
| Ingress | Allow TCP 443 from 0.0.0.0/0 | Accept HTTPS traffic from internet |
| Ingress | Allow TCP 5432 from sg-app123 | Accept PostgreSQL from app servers |
| Egress | Allow all to 0.0.0.0/0 | Allow all outbound internet access |
| Egress | Allow TCP 443 to 10.0.0.0/16 | Restrict outbound to VPC only on HTTPS |

### When should I use CIDR blocks vs security group references?

| Method | Use When | Example |
|--------|----------|---------|
| **CIDR Blocks** | Source/destination is outside AWS or you need IP-based rules | Allow from corporate VPN: `cidr_ipv4 = "203.0.113.0/24"` |
| **Security Group References** | Source/destination is another AWS resource with a security group | Allow from ALB: `referenced_security_group_id = "sg-alb123"` |
| **Self Reference** | Resources in the same security group need to communicate | Cluster nodes: `self = true` |
| **Prefix Lists** | Using AWS-managed or custom prefix lists | AWS S3 endpoints: `prefix_list_id = "pl-12345"` |

**Best Practice:** Prefer security group references over CIDR blocks when possible:
- More dynamic (handles IP changes automatically)
- Self-documenting (easier to audit)
- Works with auto-scaling resources

### How do I allow all traffic between cluster members?

Use a **self-referencing rule** with protocol `-1`:

```hcl
ingress_rules = [
  {
    description = "Allow all traffic from cluster members"
    from_port   = 0
    to_port     = 0
    ip_protocol = "-1"
    self        = true
  }
]
```

This allows any instance with this security group to communicate with any other instance that also has this security group.

### What is the difference between `all_egress_enabled` and explicit egress rules?

| Approach | Use Case |
|----------|----------|
| `all_egress_enabled = true` | General-purpose workloads that need internet access (web servers, app servers) |
| Explicit `egress_rules` | Locked-down resources (databases, internal services) that should only reach specific destinations |

**Example: Locked-down database:**

```hcl
# Database should only talk to the VPC, not the internet
all_egress_enabled = false

egress_rules = [
  {
    description = "Allow outbound to VPC only"
    from_port   = 0
    to_port     = 0
    ip_protocol = "-1"
    cidr_ipv4   = "10.0.0.0/16"
  }
]
```

### Why does this module use individual rule resources instead of inline rules?

This module uses `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` instead of inline `ingress` and `egress` blocks within `aws_security_group` for several reasons:

| Benefit | Explanation |
|---------|-------------|
| **Better State Management** | Each rule is a separate resource, so adding/removing rules does not affect other rules |
| **Quota Clarity** | AWS has a default limit of 60 rules per security group; separate resources make this easier to track |
| **Targeted Updates** | Changing one rule does not trigger recreation of the entire security group |
| **Modern Best Practice** | AWS recommends using separate rule resources for new implementations |

### How do I reference another security group that is created in the same Terraform apply?

Use the module output directly:

```hcl
module "alb_sg" {
  source = "..."
  name   = "my-alb"
  # ... ALB security group config
}

module "ecs_sg" {
  source = "..."
  name   = "my-ecs"

  ingress_rules = [
    {
      description                  = "Allow traffic from ALB"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.security_group_id
    }
  ]
}
```

Terraform will automatically determine the correct dependency order.

## Notes

- The security group uses `create_before_destroy` lifecycle to enable zero-downtime updates.
- Each rule must specify exactly one source (ingress) or destination (egress) type.
- When using `ip_protocol = "-1"` (all protocols), set `from_port = 0` and `to_port = 0`.
- The `self` attribute creates a self-referencing rule that allows traffic from/to members of the same security group.
- Rule keys in outputs are index-based strings ("0", "1", "2", etc.) to avoid issues with unknown values at plan time.
- Valid values for `ip_protocol` are: `tcp`, `udp`, `icmp`, `icmpv6`, `-1` (all), or `all`.
- Port values must be between -1 and 65535.
- CIDR blocks are validated to ensure proper format.
- Security group IDs must start with `sg-` and prefix list IDs must start with `pl-`.
- When `all_egress_enabled = true` and `ipv4_only_egress_enabled = false`, both IPv4 and IPv6 egress rules are created.
