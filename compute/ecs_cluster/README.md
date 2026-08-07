# ECS Cluster Module

This module creates an Amazon ECS cluster with configurable capacity providers (Fargate, Fargate Spot, EC2) and optional Application Load Balancers and Network Load Balancers.

## Features

- ECS cluster with optional CloudWatch Container Insights
- Fargate capacity provider (enabled by default)
- Fargate Spot capacity provider for cost savings
- EC2 capacity provider with Auto Scaling Group and managed scaling
- Optional public (internet-facing) Application Load Balancer
- Optional private (internal) Application Load Balancer
- Optional public (internet-facing) Network Load Balancer
- Optional private (internal) Network Load Balancer
- Full launch template support for EC2 instances
- IMDSv2 enforcement for enhanced security
- Mixed instances policy with Spot support
- Automatic ALB-to-EC2 security group integration

## Usage

### Basic Fargate Cluster

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
}
```

### Fargate with Public ALB

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Enable Fargate Spot for cost savings
  fargate_spot_enabled = true
  fargate_weight      = 1
  fargate_spot_weight = 3

  # Public ALB with HTTPS
  public_albs = [
    {
      name             = "my-app-pub"
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/abc123"]
    }
  ]
}
```

### EC2 Capacity Provider

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Disable Fargate, use EC2 only
  fargate_enabled = false

  # EC2 capacity provider
  ec2_instance_type    = "t3.medium"
  ec2_min_size         = 1
  ec2_max_size         = 10
  ec2_desired_capacity = 2

  # Enable Spot instances
  ec2_spot_enabled             = true
  ec2_spot_instance_types     = ["t3.large", "t3a.medium", "t3a.large"]
  ec2_on_demand_base_capacity = 1
  ec2_on_demand_percentage_above_base = 25

  # Public ALB
  public_albs = [{ name = "my-app-pub" }]
}
```

### Mixed Capacity Providers

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Attach all capacity providers. AWS does not allow mixing Fargate and EC2
  # providers in the cluster's default strategy, so the default strategy
  # commits to a single family — EC2 here, since EC2 wins when enabled
  # (override with capacity_provider_default). Services can still
  # target FARGATE/FARGATE_SPOT via their own capacity_provider_strategies.
  fargate_enabled      = true
  fargate_spot_enabled = true

  # EC2 for baseline capacity
  ec2_instance_type    = "t3.large"
  ec2_min_size         = 2
  ec2_max_size         = 20
  ec2_desired_capacity = 2

  # Multiple ALBs: services pick one by name
  public_albs = [
    {
      name             = "my-app-pub"
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/abc123"]
    },
    {
      name             = "my-app-pub-api"
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/def456"]
    }
  ]

  private_albs = [
    {
      name             = "my-app-priv"
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/xyz789"]
    }
  ]

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### With Network Load Balancer

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Public NLB (listeners and target groups created by service modules)
  public_nlbs = [{ name = "my-app-pub-nlb" }]
}
```

### With NLB and Cross-Zone Load Balancing

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Public NLB (listeners and target groups created by service modules)
  public_nlbs = [
    {
      name                              = "my-app-pub-nlb"
      cross_zone_load_balancing_enabled = true
    }
  ]
}

# Service modules create their own listeners and target groups
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  # ... service configuration ...

  load_balancer_attachment = {
    nlb_arn = module.ecs.public_nlbs[0].arn
    nlb_listener = {
      port            = 443
      protocol        = "TLS"
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    }
    target_group = {
      port     = 8080
      protocol = "TCP"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources. Maximum length depends on enabled load balancers: 28 for public ALB, 27 for private ALB, 24 for public NLB, and 23 for private NLB. | `string` | n/a | yes |
| tags | Map of tags to assign to resources | `map(string)` | `{}` | no |
| load_balancer_deletion_protection_enabled | If true, load balancers created by this module cannot be deleted via the AWS API until this is set to false. | `bool` | `true` | no |
| vpc_id | VPC ID for ECS resources | `string` | n/a | yes |
| private_subnet_ids | Private subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| public_subnet_ids | Public subnet IDs for public ALB | `list(string)` | `[]` | no |

### ECS Cluster

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| container_insights | CloudWatch Container Insights setting. Valid values: `enhanced`, `enabled`, `disabled` | `string` | `"enhanced"` | no |
| capacity_provider_default | Family for the cluster default strategy: `ec2`, `fargate` (includes Fargate Spot when enabled), or `fargate_spot`. AWS forbids mixing Fargate and EC2 providers in one strategy. Defaults to `ec2` if EC2 is enabled, then `fargate`, then `fargate_spot` | `string` | `null` | no |

### Fargate Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| fargate_enabled | Enable Fargate capacity provider | `bool` | `true` | no |
| fargate_weight | Fargate weight in default strategy | `number` | `1` | no |
| fargate_base | Base tasks on Fargate | `number` | `0` | no |

### Fargate Spot Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| fargate_spot_enabled | Enable Fargate Spot capacity provider | `bool` | `false` | no |
| fargate_spot_weight | Fargate Spot weight in default strategy | `number` | `1` | no |
| fargate_spot_base | Base tasks on Fargate Spot | `number` | `0` | no |

### EC2 Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ec2_instance_type | EC2 instance type (null to disable) | `string` | `null` | no |
| ec2_ami_id | AMI ID (null for latest ECS-optimized) | `string` | `null` | no |
| ec2_key_name | EC2 key pair name for SSH | `string` | `null` | no |
| ec2_min_size | ASG minimum size | `number` | `0` | no |
| ec2_max_size | ASG maximum size | `number` | `10` | no |
| ec2_desired_capacity | ASG desired capacity | `number` | `1` | no |
| ec2_spot_enabled | Enable Spot instances | `bool` | `false` | no |
| ec2_spot_instance_types | Additional instance types for Spot | `list(string)` | `[]` | no |
| ec2_on_demand_base_capacity | On-Demand base capacity | `number` | `0` | no |
| ec2_on_demand_percentage_above_base | On-Demand percentage above base | `number` | `0` | no |
| ec2_root_volume_size | Root volume size in GB | `number` | `30` | no |
| ec2_root_volume_type | Root volume type | `string` | `"gp3"` | no |
| ec2_user_data | Additional user data script | `string` | `""` | no |
| ec2_imdsv2_enabled | Require IMDSv2 | `bool` | `true` | no |
| ec2_weight | EC2 weight in default strategy | `number` | `1` | no |
| ec2_base | Base tasks on EC2 | `number` | `0` | no |
| ec2_managed_termination_protection_enabled | Enable managed termination protection | `bool` | `true` | no |
| ec2_managed_scaling_enabled | Enable managed scaling | `bool` | `true` | no |
| ec2_managed_scaling_target_capacity | Target capacity percentage | `number` | `100` | no |
| ec2_security_group_ids | Additional security groups for EC2 | `list(string)` | `[]` | no |

### Application load balancers

Each cluster can create any number of public and private ALBs. Services select one by name.

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| public_albs | Public (internet-facing) ALBs, one per entry | `list(object)` | `[]` | no |
| private_albs | Private (internal) ALBs, one per entry | `list(object)` | `[]` | no |

Each ALB object supports:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| name | Load balancer name (defaults to a deterministic name derived from the cluster name and index) | `string` | `null` |
| https_enabled | Enable HTTPS listener | `bool` | `false` |
| certificate_arns | ACM certificate ARNs for HTTPS. First ARN is the default certificate; the rest are attached for SNI | `list(string)` | `[]` |
| ssl_policy | SSL policy for HTTPS | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| idle_timeout | Idle timeout in seconds | `number` | `60` |
| ingress_cidr_blocks | Allowed IPv4 CIDR blocks | `list(string)` | public: `["0.0.0.0/0"]`, private: RFC1918 ranges |
| ingress_ipv6_cidr_blocks | Allowed IPv6 CIDR blocks | `list(string)` | public: `["::/0"]`, private: `[]` |
| ingress_security_group_ids | Security group IDs allowed to access the ALB | `list(string)` | `[]` |
| access_logs_enabled | Enable access logs | `bool` | `false` |
| access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` |
| web_acl_arn | WAFv2 Web ACL ARN (public ALBs only) | `string` | `null` |

### Network load balancers

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| public_nlbs | Public (internet-facing) NLBs, one per entry | `list(object)` | `[]` | no |
| private_nlbs | Private (internal) NLBs, one per entry | `list(object)` | `[]` | no |

Each NLB object supports:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| name | Load balancer name (defaults to a deterministic name derived from the cluster name and index) | `string` | `null` |
| cross_zone_load_balancing_enabled | Enable cross-zone load balancing | `bool` | `false` |
| security_group_ids | Security groups to attach | `list(string)` | `[]` |
| access_logs_enabled | Enable access logs | `bool` | `false` |
| access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` |
| elastic_ips_enabled | Enable static IPs (public NLBs only) | `bool` | `false` |
| elastic_ip_allocation_ids | Elastic IP allocation IDs (public NLBs only) | `list(string)` | `[]` |

## Outputs

### ECS Cluster

| Name | Description |
|------|-------------|
| cluster_id | The ID of the ECS cluster |
| cluster_arn | The ARN of the ECS cluster |
| cluster_name | The name of the ECS cluster |

### Capacity Providers

| Name | Description |
|------|-------------|
| fargate_capacity_provider_name | Fargate capacity provider name |
| fargate_spot_capacity_provider_name | Fargate Spot capacity provider name |
| ec2_capacity_provider_name | EC2 capacity provider name |
| ec2_capacity_provider_arn | EC2 capacity provider ARN |

### EC2 Infrastructure

| Name | Description |
|------|-------------|
| launch_template_id | EC2 launch template ID |
| launch_template_arn | EC2 launch template ARN |
| autoscaling_group_arn | Auto Scaling Group ARN |
| autoscaling_group_name | Auto Scaling Group name |
| ecs_instance_role_arn | IAM role ARN for EC2 instances |
| ecs_instance_role_name | IAM role name for EC2 instances |
| ecs_instance_security_group_id | Security group ID for EC2 instances |

### Load balancers

| Name | Description |
|------|-------------|
| public_albs | List of public ALB records (name, arn, id, dns_name, zone_id, arn_suffix, security_group_id, http_listener_arn, https_listener_arn, https_enabled) |
| private_albs | List of private ALB records (same shape as public_albs) |
| public_albs_by_name | Public ALB records keyed by name |
| private_albs_by_name | Private ALB records keyed by name |
| public_alb_options / private_alb_options | ALB names, for selection UIs |
| public_nlbs | List of public NLB records (name, arn, id, dns_name, zone_id, arn_suffix, security_group_id) |
| private_nlbs | List of private NLB records (same shape as public_nlbs) |
| public_nlbs_by_name / private_nlbs_by_name | NLB records keyed by name |
| public_nlb_options / private_nlb_options | NLB names, for selection UIs |

### Deprecated singleton outputs

The pre-2.0 singleton outputs (`public_alb_arn`, `public_alb_dns_name`, `public_alb_http_listener_arn`, `private_alb_arn`, `public_nlb_arn`, etc.) are still exposed for backward compatibility and return the first load balancer of the corresponding list, or `null` when the list is empty.

## Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ECS Cluster                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Capacity Providers                               │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │    │
│  │  │   Fargate    │  │ Fargate Spot │  │    EC2 Capacity Provider │  │    │
│  │  │  (Optional)  │  │  (Optional)  │  │       (Optional)         │  │    │
│  │  └──────────────┘  └──────────────┘  └────────────┬─────────────┘  │    │
│  │                                                    │                │    │
│  └────────────────────────────────────────────────────│────────────────┘    │
│                                                       │                      │
│  ┌────────────────────────────────────────────────────▼────────────────────┐│
│  │                         EC2 Infrastructure                               ││
│  │                                                                          ││
│  │  ┌──────────────┐  ┌──────────────────┐  ┌────────────────────────────┐ ││
│  │  │   Launch     │  │   Auto Scaling   │  │    IAM Role & Instance     │ ││
│  │  │   Template   │──│      Group       │──│        Profile             │ ││
│  │  └──────────────┘  └──────────────────┘  └────────────────────────────┘ ││
│  └──────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────────┐│
│  │                       Load Balancers (Optional)                          ││
│  │                                                                          ││
│  │  ┌──────────────────────────────┐  ┌──────────────────────────────────┐ ││
│  │  │        Public ALB            │  │          Private ALB             │ ││
│  │  │    (Internet-facing)         │  │         (Internal)               │ ││
│  │  └──────────────────────────────┘  └──────────────────────────────────┘ ││
│  │                                                                          ││
│  │  ┌──────────────────────────────┐  ┌──────────────────────────────────┐ ││
│  │  │        Public NLB            │  │          Private NLB             │ ││
│  │  │    (Internet-facing)         │  │         (Internal)               │ ││
│  │  └──────────────────────────────┘  └──────────────────────────────────┘ ││
│  └──────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    COMPUTE/ECS_CLUSTER TERRAFORM MODULE                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │        NETWORK                  │   │      ECS CLUSTER                        │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • vpc_id (required)             │   │ • container_insights                     │  ║
║  │ • tags                      │   │ • private_subnet_ids (required) │   └─────────────────────────────────────────┘  ║
║  └─────────────────────────────┘   │ • public_subnet_ids             │                                                 ║
║                                    └─────────────────────────────────┘                                                 ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │   FARGATE CAPACITY          │   │   FARGATE SPOT CAPACITY         │   │      EC2 CAPACITY PROVIDER              │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • fargate_enabled            │   │ • fargate_spot_enabled           │   │ • ec2_instance_type                     │  ║
║  │ • fargate_weight            │   │ • fargate_spot_weight           │   │ • ec2_ami_id                            │  ║
║  │ • fargate_base              │   │ • fargate_spot_base             │   │ • ec2_key_name                          │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   │ • ec2_min_size, ec2_max_size            │  ║
║                                                                          │ • ec2_desired_capacity                  │  ║
║                                                                          │ • ec2_spot_enabled                       │  ║
║                                                                          │ • ec2_spot_instance_types               │  ║
║                                                                          │ • ec2_on_demand_base_capacity           │  ║
║                                                                          │ • ec2_on_demand_percentage_above_base   │  ║
║                                                                          │ • ec2_root_volume_size/type             │  ║
║                                                                          │ • ec2_user_data, ec2_imdsv2_enabled      │  ║
║                                                                          │ • ec2_weight, ec2_base                  │  ║
║                                                                          │ • ec2_managed_termination_*             │  ║
║                                                                          │ • ec2_managed_scaling_enabled           │  ║
║                                                                          │ • ec2_managed_scaling_target_capacity   │  ║
║                                                                          │ • ec2_security_group_ids                │  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                              LOAD BALANCER CONFIG                                                 │  ║
║  ├────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────┤  ║
║  │           PUBLIC ALB                       │                    PRIVATE ALB                                      │  ║
║  ├────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤  ║
║  │ • public_albs (array)                       │ • private_albs (array)                                              │  ║
║  │ • per-item https_enabled                    │ • per-item settings (below)                                          │  ║
║  │ • public_alb_certificate_arns              │ • private_alb_certificate_arns                                      │  ║
║  │ • public_alb_ssl_policy                    │ • private_alb_ssl_policy                                            │  ║
║  │ • public_alb_idle_timeout                  │ • private_alb_idle_timeout                                          │  ║
║  │ • public_alb_ingress_cidr_blocks           │ • private_alb_ingress_cidr_blocks                                   │  ║
║  │ • public_alb_access_logs_enabled            │ • private_alb_access_logs_enabled                                    │  ║
║  │ • public_alb_access_logs_bucket_arn        │ • private_alb_access_logs_bucket_arn                                │  ║
║  │ • public_alb_web_acl_arn                   │                                                                     │  ║
║  ├────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤  ║
║  │           PUBLIC NLB                       │                    PRIVATE NLB                                      │  ║
║  ├────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤  ║
║  │ • public_nlbs (array)                       │ • private_nlbs (array)                                              │  ║
║  │ • public_nlb_enable_cross_zone_load_bal... │ • private_nlb_cross_zone_load_balancing_enabled                      │  ║
║  │ • public_nlb_security_group_ids            │ • private_nlb_security_group_ids                                    │  ║
║  │ • public_nlb_access_logs_enabled            │ • private_nlb_access_logs_enabled                                    │  ║
║  │ • public_nlb_access_logs_bucket_arn        │ • private_nlb_access_logs_bucket_arn                                │  ║
║  │ • public_nlb_elastic_ips_enabled            │ • private_nlb_elastic_ips_enabled                                    │  ║
║  │ • public_nlb_elastic_ip_allocation_ids     │ • private_nlb_elastic_ip_allocation_ids                             │  ║
║  └────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                     LOCALS                                                             ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │ • default_tags = { ManagedBy = "terraform", Module = "compute/ecs_cluster" }                                     │  ║
║  │ • tags = merge(default_tags, var.tags)                                                                           │  ║
║  │ • cluster_name = var.name                                                                                        │  ║
║  │                                                                                                                   │  ║
║  │ FEATURE FLAGS:                                                                                                    │  ║
║  │ • enable_ec2 = var.ec2_instance_type != null                                                                     │  ║
║  │ • ec2_capacity_provider_name = enable_ec2 ? "${var.name}-ec2" : null                                             │  ║
║  │                                                                                                                   │  ║
║  │ CAPACITY PROVIDER STRATEGY:                                                                                       │  ║
║  │ • capacity_provider_strategy = single family via capacity_provider_default                                │  ║
║  │                                                                                                                   │  ║
║  │ EC2 CONFIGURATION:                                                                                                │  ║
║  │ • ecs_user_data = base64encode(ECS_CLUSTER config + custom user_data)                                            │  ║
║  │ • ec2_instance_types = concat([var.ec2_instance_type], var.ec2_spot_instance_types)                              │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                         aws_ecs_cluster.this                                                 │    ║
║    │                                           (CORE RESOURCE)                                                    │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ Creates ECS cluster with Container Insights setting                                                          │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                               aws_ecs_cluster_capacity_providers.this                                        │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ Associates capacity providers (FARGATE, FARGATE_SPOT, EC2) with default strategy                             │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║         ┌─────────────────────────────────────────────────┼─────────────────────────────────────────────────┐          ║
║         │                                                 │                                                 │          ║
║         ▼                                                 ▼                                                 ▼          ║
║    ┌────────────────────────┐    ┌─────────────────────────────────────────────────────────────────────────────────┐  ║
║    │  DATA SOURCES          │    │                      EC2 INFRASTRUCTURE (conditional: enable_ec2)               │  ║
║    ├────────────────────────┤    ├─────────────────────────────────────────────────────────────────────────────────┤  ║
║    │ • aws_ssm_parameter    │    │                                                                                 │  ║
║    │   .ecs_optimized_ami   │    │  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐  │  ║
║    │   (conditional)        │    │  │ aws_iam_role         │  │ aws_iam_instance     │  │ aws_iam_role_policy  │  │  ║
║    │                        │    │  │ .ecs_instance[0]     │  │ _profile             │  │ _attachment (x2)     │  │  ║
║    │ • aws_region.current   │    │  │                      │──│ .ecs_instance[0]     │  │ • ECS for EC2 Role   │  │  ║
║    │ • aws_caller_identity  │    │  │ EC2 assume role      │  │                      │  │ • SSM Managed Core   │  │  ║
║    │   .current             │    │  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘  │  ║
║    └────────────────────────┘    │                                        │                                        │  ║
║                                  │                                        ▼                                        │  ║
║                                  │  ┌─────────────────────────────────────────────────────────────────────────┐   │  ║
║                                  │  │                    module.ecs_instance_security_group[0]                 │   │  ║
║                                  │  │                        (networking/security-groups)                      │   │  ║
║                                  │  ├─────────────────────────────────────────────────────────────────────────┤   │  ║
║                                  │  │ • Allow all egress                                                       │   │  ║
║                                  │  │ • Allow inbound from public ALB (if enabled)                             │   │  ║
║                                  │  │ • Allow inbound from private ALB (if enabled)                            │   │  ║
║                                  │  └─────────────────────────────────────────────────────────────────────────┘   │  ║
║                                  │                                        │                                        │  ║
║                                  │                                        ▼                                        │  ║
║                                  │  ┌─────────────────────────────────────────────────────────────────────────┐   │  ║
║                                  │  │                       aws_launch_template.ecs[0]                         │   │  ║
║                                  │  ├─────────────────────────────────────────────────────────────────────────┤   │  ║
║                                  │  │ • AMI (ECS-optimized or custom)     • IAM instance profile               │   │  ║
║                                  │  │ • Instance type                     • Security groups                    │   │  ║
║                                  │  │ • User data (ECS config)            • Block devices (encrypted)          │   │  ║
║                                  │  │ • Metadata options (IMDSv2)         • Monitoring enabled                 │   │  ║
║                                  │  └─────────────────────────────────────────────────────────────────────────┘   │  ║
║                                  │                                        │                                        │  ║
║                                  │                                        ▼                                        │  ║
║                                  │  ┌─────────────────────────────────────────────────────────────────────────┐   │  ║
║                                  │  │                      module.ecs_autoscaling[0]                           │   │  ║
║                                  │  │                        (compute/autoscaling)                             │   │  ║
║                                  │  ├─────────────────────────────────────────────────────────────────────────┤   │  ║
║                                  │  │ • Uses launch template             • ECS managed tags                    │   │  ║
║                                  │  │ • min/max/desired capacity         • Protect from scale-in               │   │  ║
║                                  │  │ • Mixed instances policy (Spot)    • Instance refresh (Rolling)          │   │  ║
║                                  │  └─────────────────────────────────────────────────────────────────────────┘   │  ║
║                                  │                                        │                                        │  ║
║                                  │                                        ▼                                        │  ║
║                                  │  ┌─────────────────────────────────────────────────────────────────────────┐   │  ║
║                                  │  │                    aws_ecs_capacity_provider.ec2[0]                      │   │  ║
║                                  │  ├─────────────────────────────────────────────────────────────────────────┤   │  ║
║                                  │  │ • Links ASG to ECS cluster         • Managed scaling configuration       │   │  ║
║                                  │  │ • Managed termination protection   • Step size 1-10                      │   │  ║
║                                  │  └─────────────────────────────────────────────────────────────────────────┘   │  ║
║                                  └─────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║    ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║    │                                         LOAD BALANCERS (all conditional)                                      │   ║
║    ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤   ║
║    │                                                                                                               │   ║
║    │  ┌────────────────────────────────┐  ┌────────────────────────────────┐                                      │   ║
║    │  │  module.public_alb["name"]     │  │  module.private_alb["name"]    │                                      │   ║
║    │  │  (networking/alb)              │  │  (networking/alb)              │                                      │   ║
║    │  ├────────────────────────────────┤  ├────────────────────────────────┤                                      │   ║
║    │  │ • Internet-facing              │  │ • Internal                     │                                      │   ║
║    │  │ • Public subnets               │  │ • Private subnets              │                                      │   ║
║    │  │ • HTTP + HTTPS listeners       │  │ • HTTP + HTTPS listeners       │                                      │   ║
║    │  │ • HTTP→HTTPS redirect          │  │ • HTTP→HTTPS redirect          │                                      │   ║
║    │  │ • WAF integration              │  │                                │                                      │   ║
║    │  └────────────────────────────────┘  └────────────────────────────────┘                                      │   ║
║    │                                                                                                               │   ║
║    │  ┌────────────────────────────────┐  ┌────────────────────────────────┐                                      │   ║
║    │  │  module.public_nlb["name"]     │  │  module.private_nlb["name"]    │                                      │   ║
║    │  │  (networking/nlb)              │  │  (networking/nlb)              │                                      │   ║
║    │  ├────────────────────────────────┤  ├────────────────────────────────┤                                      │   ║
║    │  │ • Internet-facing              │  │ • Internal                     │                                      │   ║
║    │  │ • Public subnets               │  │ • Private subnets              │                                      │   ║
║    │  │ • Elastic IPs (optional)       │  │ • Elastic IPs (optional)       │                                      │   ║
║    │  │ • Cross-zone LB (optional)     │  │ • Cross-zone LB (optional)     │                                      │   ║
║    │  └────────────────────────────────┘  └────────────────────────────────┘                                      │   ║
║    │                                                                                                               │   ║
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
║  │           ECS CLUSTER                   │   │        CAPACITY PROVIDERS               │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • cluster_id                            │   │ • fargate_capacity_provider_name        │                            ║
║  │ • cluster_arn                           │   │ • fargate_spot_capacity_provider_name   │                            ║
║  │ • cluster_name                          │   │ • ec2_capacity_provider_name            │                            ║
║  └─────────────────────────────────────────┘   │ • ec2_capacity_provider_arn             │                            ║
║                                                └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │       EC2 INFRASTRUCTURE                │   │           PUBLIC ALB                    │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • launch_template_id                    │   │ • public_alb_arn                        │                            ║
║  │ • launch_template_arn                   │   │ • public_alb_id                         │                            ║
║  │ • autoscaling_group_arn                 │   │ • public_alb_dns_name                   │                            ║
║  │ • autoscaling_group_name                │   │ • public_alb_zone_id                    │                            ║
║  │ • ecs_instance_role_arn                 │   │ • public_alb_arn_suffix                 │                            ║
║  │ • ecs_instance_role_name                │   │ • public_alb_security_group_id          │                            ║
║  │ • ecs_instance_security_group_id        │   │ • public_alb_http_listener_arn          │                            ║
║  └─────────────────────────────────────────┘   │ • public_alb_https_listener_arn         │                            ║
║                                                └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │          PRIVATE ALB                    │   │           PUBLIC NLB                    │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • private_alb_arn                       │   │ • public_nlb_arn                        │                            ║
║  │ • private_alb_id                        │   │ • public_nlb_id                         │                            ║
║  │ • private_alb_dns_name                  │   │ • public_nlb_dns_name                   │                            ║
║  │ • private_alb_zone_id                   │   │ • public_nlb_zone_id                    │                            ║
║  │ • private_alb_arn_suffix                │   │ • public_nlb_arn_suffix                 │                            ║
║  │ • private_alb_security_group_id         │   └─────────────────────────────────────────┘                            ║
║  │ • private_alb_http_listener_arn         │                                                                          ║
║  │ • private_alb_https_listener_arn        │   ┌─────────────────────────────────────────┐                            ║
║  └─────────────────────────────────────────┘   │          PRIVATE NLB                    │                            ║
║                                                ├─────────────────────────────────────────┤                            ║
║                                                │ • private_nlb_arn                       │                            ║
║                                                │ • private_nlb_id                        │                            ║
║                                                │ • private_nlb_dns_name                  │                            ║
║                                                │ • private_nlb_zone_id                   │                            ║
║                                                │ • private_nlb_arn_suffix                │                            ║
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
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║              ┌──────────────────────────────────────┼──────────────────────────────────────┐                           ║
║              │                                      │                                      │                           ║
║              ▼                                      ▼                                      ▼                           ║
║  var.vpc_id ───────────────────────►  local.cluster_name ─────────────────►  local.ec2_capacity_provider_name         ║
║              │                              │                                      │                                   ║
║              │                              ▼                                      │                                   ║
║              │                   ┌──────────────────────────┐                      │                                   ║
║              │                   │  aws_ecs_cluster.this    │                      │                                   ║
║              │                   └────────────┬─────────────┘                      │                                   ║
║              │                                │                                    │                                   ║
║              │                                ▼                                    ▼                                   ║
║              │    var.fargate_enabled ────►┌──────────────────────────────────────────────┐                             ║
║              │    var.fargate_spot_enabled►│   aws_ecs_cluster_capacity_providers.this   │                             ║
║              │    local.enable_ec2 ──────►│   (single-family default strategy)          │                             ║
║              │                            └──────────────────────────────────────────────┘                             ║
║              │                                                                                                         ║
║              │                        ┌────────────────────────────────────────────────────┐                           ║
║              │                        │               EC2 INFRASTRUCTURE                   │                           ║
║              │                        └────────────────────────────────────────────────────┘                           ║
║              │                                           │                                                             ║
║              │                     ┌─────────────────────┼─────────────────────┐                                       ║
║              │                     ▼                     ▼                     ▼                                       ║
║              │         var.ec2_instance_type    var.ec2_ami_id    var.ec2_user_data                                    ║
║              │                     │                     │                     │                                       ║
║              │                     └─────────────────────┼─────────────────────┘                                       ║
║              │                                           ▼                                                             ║
║              │                              ┌──────────────────────────┐                                               ║
║              │    data.aws_ssm_parameter ──►│ aws_launch_template.ecs  │                                               ║
║              │    .ecs_optimized_ami        └────────────┬─────────────┘                                               ║
║              │                                           │                                                             ║
║              │                                           ▼                                                             ║
║              │    var.ec2_min/max_size ────►┌──────────────────────────┐                                               ║
║              │    var.ec2_desired_capacity ►│ module.ecs_autoscaling   │                                               ║
║              │    var.ec2_spot_enabled ─────►│ (compute/autoscaling)    │                                               ║
║              │    var.private_subnet_ids ──►└────────────┬─────────────┘                                               ║
║              │                                           │                                                             ║
║              │                                           ▼                                                             ║
║              │    var.ec2_managed_scaling_*►┌──────────────────────────────────┐                                       ║
║              │    var.ec2_managed_termin...►│ aws_ecs_capacity_provider.ec2    │                                       ║
║              │                              └──────────────────────────────────┘                                       ║
║              │                                                                                                         ║
║              │                        ┌────────────────────────────────────────────────────┐                           ║
║              │                        │                 LOAD BALANCERS                     │                           ║
║              │                        └────────────────────────────────────────────────────┘                           ║
║              │                                                                                                         ║
║              │    length(var.public_albs) ───►┌──────────────────────────┐                                              ║
║              │    var.public_albs[*] ───────►│ module.public_alb        │                                              ║
║              │    var.public_subnet_ids ────►└──────────────────────────┘                                              ║
║              │                                                                                                         ║
║              │    length(var.private_albs) ──►┌──────────────────────────┐                                              ║
║              │    var.private_albs[*] ──────►│ module.private_alb       │                                              ║
║              └──────────────────────────────►└──────────────────────────┘                                              ║
║              │                                                                                                         ║
║              │    length(var.public_nlbs) ───►┌──────────────────────────┐                                              ║
║              │    var.public_nlbs[*] ───────►│ module.public_nlb        │                                              ║
║              │    var.public_subnet_ids ────►└──────────────────────────┘                                              ║
║              │                                                                                                         ║
║              │    length(var.private_nlbs) ──►┌──────────────────────────┐                                              ║
║              │    var.private_nlbs[*] ──────►│ module.private_nlb       │                                              ║
║              └──────────────────────────────►└──────────────────────────┘                                              ║
║                                                                                                                        ║
║                                                         │                                                              ║
║                                                         ▼                                                              ║
║                                                  MODULE OUTPUTS                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_ecs_cluster` | 1 | Core ECS cluster resource |
| `aws_ecs_cluster_capacity_providers` | 1 | Associates capacity providers with cluster |
| `aws_ecs_capacity_provider` (EC2) | 0 or 1 | EC2 capacity provider with managed scaling |
| `aws_launch_template` | 0 or 1 | EC2 instance configuration |
| `aws_iam_role` (ECS instance) | 0 or 1 | IAM role for EC2 instances |
| `aws_iam_instance_profile` | 0 or 1 | Instance profile for EC2 instances |
| `aws_iam_role_policy_attachment` | 0 or 2 | ECS and SSM policy attachments |
| `module.ecs_autoscaling` | 0 or 1 | Auto Scaling Group for EC2 instances |
| `module.ecs_instance_security_group` | 0 or 1 | Security group for EC2 instances |
| `module.public_alb` | 0 to N (one per entry, keyed by name) | Public Application Load Balancers |
| `module.private_alb` | 0 to N (one per entry, keyed by name) | Private Application Load Balancers |
| `module.public_nlb` | 0 to N (one per entry, keyed by name) | Public Network Load Balancers |
| `module.private_nlb` | 0 to N (one per entry, keyed by name) | Private Network Load Balancers |

## FAQ

### When should I use Fargate vs EC2 capacity providers?

ECS supports three types of capacity providers, each with distinct trade-offs:

| Provider | Best For | Pros | Cons |
|----------|----------|------|------|
| **Fargate** | Most workloads | No infrastructure management, fast scaling, pay-per-task | Higher cost per vCPU/memory |
| **Fargate Spot** | Fault-tolerant workloads | Up to 70% cost savings | Can be interrupted with 2-minute warning |
| **EC2** | Specialized needs | Full instance control, GPUs, lower cost at scale | Infrastructure management overhead |

**Choose Fargate when:**
- You want to focus on applications, not infrastructure
- Workloads are variable or unpredictable
- You need fast scaling without warm-up time

**Choose EC2 when:**
- You need GPU instances
- You have predictable, high-volume workloads (cost optimization)
- You need specific instance types or kernel configurations
- You require persistent local storage

**Example: Cost-optimized mixed cluster**

AWS does not allow a single capacity provider strategy to mix Fargate and EC2
(Auto Scaling group) providers, so the cluster's default strategy commits to
one family (`capacity_provider_default`). To mix families across
workloads, attach both to the cluster and pick the family per service:

```hcl
# EC2 is the cluster default; specific services opt into Fargate Spot
module "ecs" {
  source = "..."

  fargate_enabled      = false    # Disable standard Fargate
  fargate_spot_enabled = true     # Attached for services that want Spot

  ec2_instance_type = "m5.large" # EC2 wins the default strategy when enabled
}

module "batch_service" {
  source = ".../compute/ecs_service"

  # ... service configuration ...

  # Override the cluster default for this service only
  capacity_provider_strategies = [
    { capacity_provider = "FARGATE_SPOT", weight = 1 }
  ]
}
```

### How do capacity provider weights and base work?

The **base** and **weight** parameters control how ECS distributes tasks across capacity providers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Task Distribution Algorithm                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. First, satisfy BASE requirements (guaranteed tasks per provider)         │
│                                                                              │
│     Example: fargate_base=2, fargate_spot_weight=1                           │
│     → First 2 tasks on Fargate, then split with Fargate Spot                 │
│                                                                              │
│  2. Then, distribute remaining tasks by WEIGHT ratio                         │
│                                                                              │
│     Example: fargate_weight=1, fargate_spot_weight=3                         │
│     → Additional tasks: 25% Fargate, 75% Fargate Spot                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Example scenarios:**

| Scenario | Configuration | Result |
|----------|---------------|--------|
| Fargate only | `fargate_enabled=true` | All tasks on Fargate |
| Cost savings | `fargate_weight=1, fargate_spot_weight=3` | 25% Fargate, 75% Fargate Spot |
| EC2 default | `ec2_instance_type="m5.large"` | Default strategy is EC2; services may target Fargate via their own strategy |

Note: base/weight only combine providers within the same family (Fargate +
Fargate Spot). A strategy cannot mix Fargate and EC2 providers — the cluster
default commits to one family via `capacity_provider_default`.

### How does EC2 managed scaling work?

When EC2 capacity provider is enabled, ECS uses **Capacity Provider Managed Scaling** to automatically adjust the Auto Scaling Group:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Managed Scaling Flow                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. ECS tracks CapacityProviderReservation metric                            │
│     (Running Tasks / Available Capacity × 100)                               │
│                                                                              │
│  2. When reservation exceeds target_capacity (default: 100%):                │
│     → ECS scales OUT the ASG                                                 │
│                                                                              │
│  3. When reservation falls below target_capacity:                            │
│     → ECS scales IN the ASG (respecting termination protection)              │
│                                                                              │
│  Configuration:                                                              │
│  • ec2_managed_scaling_enabled = true                                         │
│  • ec2_managed_scaling_target_capacity = 100 (%)                             │
│  • ec2_managed_termination_protection_enabled = true                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Target capacity recommendations:**

| Target | Use Case |
|--------|----------|
| 100% | Maximum density, cost-optimized |
| 80% | Buffer for burst capacity |
| 50% | High availability, rapid scaling |

### Can I use both ALB and NLB?

Yes! You can enable multiple load balancers for different use cases:

```hcl
module "ecs" {
  source = "..."

  # ALB for HTTP/HTTPS traffic with path-based routing
  public_albs = [
    {
      name             = "my-app-pub"
      https_enabled    = true
      certificate_arns = ["arn:aws:acm:..."]
    }
  ]

  # NLB for TCP/UDP traffic or static IPs
  public_nlbs = [
    {
      name                      = "my-app-pub-nlb"
      elastic_ips_enabled       = true
      elastic_ip_allocation_ids = ["eipalloc-abc123", "eipalloc-def456"]
    }
  ]
}
```

| Feature | ALB | NLB |
|---------|-----|-----|
| Protocols | HTTP, HTTPS, WebSocket | TCP, UDP, TLS |
| Path-based routing | Yes | No |
| Static IPs | No | Yes (with Elastic IPs) |
| Latency | Higher | Ultra-low |
| SSL termination | Yes | Yes (TLS) |
| Health checks | HTTP/HTTPS | TCP/HTTP |

### How do I enable Spot instances for EC2?

Enable Spot instances with the mixed instances policy:

```hcl
module "ecs" {
  source = "..."

  ec2_instance_type    = "m5.large"       # Primary instance type
  ec2_spot_enabled      = true

  # Additional Spot instance types for diversity
  ec2_spot_instance_types = [
    "m5.xlarge",
    "m5a.large",
    "m5a.xlarge",
    "m4.large"
  ]

  # Capacity allocation
  ec2_on_demand_base_capacity         = 2    # Always keep 2 On-Demand
  ec2_on_demand_percentage_above_base = 25   # 25% On-Demand above base
}
```

This creates a mixed instances policy with:
- 2 On-Demand instances guaranteed
- 25% On-Demand, 75% Spot for additional capacity
- Capacity-optimized allocation strategy for best Spot availability

### How are security groups configured for EC2 instances?

The module automatically creates a security group for EC2 instances that:

1. **Allows all egress** (required for ECS agent communication)
2. **Allows inbound from ALBs** (if enabled) - automatically configured

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Security Group Configuration                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ECS Instance Security Group:                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Egress: 0.0.0.0/0 (all traffic)                                    │    │
│  │                                                                      │    │
│  │  Ingress (dynamic):                                                  │    │
│  │    ├─ From each public ALB security group                             │    │
│  │    └─ From each private ALB security group                           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  Additional security groups can be attached via:                             │
│  ec2_security_group_ids = ["sg-xxx", "sg-yyy"]                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Notes

- The EC2 capacity provider is only created when `ec2_instance_type` is specified
- The cluster default capacity provider strategy commits to a single family (AWS forbids mixing Fargate and EC2 providers in one strategy); control it with `capacity_provider_default`
- By default, uses the latest ECS-optimized Amazon Linux 2023 AMI
- EC2 instances automatically register with the ECS cluster via user data
- IMDSv2 is enforced by default for enhanced security
- The EC2 security group automatically allows traffic from enabled ALBs
- NLBs require explicit target group and listener configuration (passthrough to the NLB module)
- NLB target groups support TCP, TLS, UDP, and TCP_UDP protocols
- ALBs require at least 2 subnets in different availability zones
- The `name` variable is limited to 28 characters to ensure ALB names don't exceed AWS limits
- EBS volumes on EC2 instances are encrypted by default
- Managed termination protection prevents ECS from terminating instances with running tasks

## Migrating from 1.x (single load balancer inputs)

Version 2.0.0 replaces the singleton `public_alb_*`/`private_alb_*`/`*_nlb_*` variables with the
`public_albs`, `private_albs`, `public_nlbs`, and `private_nlbs` object arrays. Load balancer module
instances are keyed by their resolved name (`for_each`) instead of a positional index (`count`), so
Terraform addresses change from `module.public_alb[0]` to `module.public_alb["<name>"]`.

For existing state, move each load balancer to its new address before applying, e.g.:

```bash
tofu state mv 'module.public_alb[0]' 'module.public_alb["my-cluster-pub"]'
```

The default resolved name for the first entry is `<name>-pub` (public ALB), `<name>-priv`
(private ALB), `<name>-pub-nlb` (public NLB), and `<name>-priv-nlb` (private NLB) when no explicit
`name` is set. Without the state move, Terraform plans to destroy and recreate the load balancer.
