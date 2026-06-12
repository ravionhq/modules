# ECS Service Module

This module creates an Amazon ECS service with a placeholder task definition, load balancer integration, auto scaling, and service discovery. It supports both rolling and blue/green deployment strategies.

**Note:** This module provisions infrastructure with a placeholder container (hello-world). An external deployment controller (e.g. CodeDeploy or another CI/CD tool) is expected to deploy the actual application by updating the task definition.

## Features

- ECS service with configurable deployment strategies (rolling or blue/green)
- Placeholder task definition (hello-world) - the external deployment controller updates with the actual application
- IAM roles for task execution and task roles with optional ECS Exec support
- Security group for ECS tasks with configurable ingress rules
- Target group creation for ALB/NLB integration
- Listener rule configuration for path-based and host-based routing
- NLB listener creation with TLS support
- Application Auto Scaling with target tracking and scheduled scaling
- AWS Cloud Map service discovery integration
- Blue/green deployment infrastructure (managed by an external deployment controller)
- Support for EFS, S3 Files, Docker, and EC2 host path volume configurations
- Capacity provider strategy support for mixed Fargate/EC2 deployments

## Usage

### Basic Fargate Service

```hcl
module "ecs_cluster" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name               = "my-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  public_alb_enabled       = true
  public_alb_https_enabled = true
  public_alb_certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/abc123"]
}

module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "api"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  # Task configuration
  task_cpu       = 256
  task_memory    = 512
  container_port = 80  # Port for the placeholder container

  # Load balancer
  load_balancer_attachment = {
    target_group = {
      port     = 80
      protocol = "HTTP"
      health_check = {
        path = "/"
      }
    }
    listener_rules = [{
      listener_arn = module.ecs_cluster.public_alb_https_listener_arn
      conditions = [{
        type   = "path-pattern"
        values = ["/api/*"]
      }]
    }]
  }

  # Auto scaling
  auto_scaling = {
    min_capacity = 1
    max_capacity = 10
    target_tracking = [{
      policy_name       = "cpu"
      target_value      = 70
      predefined_metric = "ECSServiceAverageCPUUtilization"
    }]
  }
}

# After infrastructure is provisioned, deploy the actual application via your external deployment controller
```

### Blue/Green Deployment

```hcl
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name            = "api"
  cluster_arn     = module.ecs_cluster.cluster_arn
  vpc_id          = "vpc-12345678"
  subnet_ids      = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  deployment_type = "blue_green"

  task_cpu       = 512
  task_memory    = 1024
  container_port = 8080

  load_balancer_attachment = {
    target_group = {
      port     = 8080
      protocol = "HTTP"
    }
    listener_rules = [{
      listener_arn = module.ecs_cluster.public_alb_https_listener_arn
      conditions = [{
        type   = "host-header"
        values = ["api.example.com"]
      }]
    }]
  }
}

# Use the outputs to configure an external deployment controller
# module.api_service.blue_target_group_arn
# module.api_service.green_target_group_arn
```

### With Service Discovery

```hcl
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "internal.local"
  vpc  = "vpc-12345678"
}

module "backend_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "backend"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  task_cpu       = 256
  task_memory    = 512
  container_port = 3000

  # No load balancer, just service discovery
  load_balancer_attachment = null

  service_discovery = {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
  }
}

# Service is now accessible at: backend.internal.local
```

### With NLB (TCP/TLS)

```hcl
module "tcp_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "tcp-service"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  task_cpu       = 512
  task_memory    = 1024
  container_port = 5000

  load_balancer_attachment = {
    target_group = {
      port     = 5000
      protocol = "TCP"
    }
    nlb_listener = {
      nlb_arn  = aws_lb.nlb.arn
      port     = 5000
      protocol = "TCP"
    }
  }
}
```

### With Auto Scaling and Scheduled Actions

```hcl
module "worker_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "worker"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  task_cpu       = 1024
  task_memory    = 2048
  container_port = 8080

  auto_scaling = {
    min_capacity = 2
    max_capacity = 50

    target_tracking = [
      {
        policy_name       = "cpu"
        target_value      = 70
        predefined_metric = "ECSServiceAverageCPUUtilization"
      },
      {
        policy_name       = "memory"
        target_value      = 80
        predefined_metric = "ECSServiceAverageMemoryUtilization"
      }
    ]

    scheduled = [
      {
        name         = "scale-up-morning"
        schedule     = "cron(0 9 ? * MON-FRI *)"
        min_capacity = 10
        max_capacity = 50
        timezone     = "America/New_York"
      },
      {
        name         = "scale-down-evening"
        schedule     = "cron(0 18 ? * MON-FRI *)"
        min_capacity = 2
        max_capacity = 10
        timezone     = "America/New_York"
      }
    ]
  }
}
```

### Minimal Configuration

```hcl
module "worker_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "worker"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  # Uses defaults: 256 CPU, 512 MiB memory, port 80
  # Placeholder hello-world container will be deployed initially
  # The external deployment controller will update with the actual worker container
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
| name | Name for the ECS service and related resources | `string` | n/a | yes |
| tags | Map of tags to assign to resources | `map(string)` | `{}` | no |

### Network

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_id | VPC ID where the service will run | `string` | n/a | yes |
| subnet_ids | Subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| assign_public_ip | Assign public IP to tasks (for Fargate in public subnets without NAT) | `bool` | `false` | no |
| security_group_ids | Additional security group IDs to attach | `list(string)` | `[]` | no |
| allowed_cidr_blocks | CIDR blocks allowed to access the service | `list(string)` | `[]` | no |

### ECS Cluster

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_arn | ECS cluster ARN | `string` | n/a | yes |

### Task Definition

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| task_cpu | CPU units for the task (256, 512, 1024, 2048, 4096, 8192, 16384) | `number` | `256` | no |
| task_memory | Memory (MiB) for the task (512-122880) | `number` | `512` | no |
| container_port | Port for the placeholder container | `number` | `80` | no |
| launch_type | Launch type (FARGATE or EC2) | `string` | `"FARGATE"` | no |
| network_mode | Docker networking mode (awsvpc, bridge, host, none) | `string` | `"awsvpc"` | no |
| requires_compatibilities | Launch type compatibility requirements | `list(string)` | `["FARGATE"]` | no |
| runtime_platform | Runtime platform configuration (OS family, CPU architecture) | `object` | `{}` | no |
| volumes | List of volume definitions (EFS, S3 Files, Docker, or EC2 host path) | `list(object)` | `[]` | no |

### CloudWatch Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| log_retention_days | Days to retain CloudWatch logs (0 = retain indefinitely) | `number` | `30` | no |
| log_kms_key_id | KMS key ARN for encrypting the log group (null = default encryption) | `string` | `null` | no |

### IAM

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| execution_role_arn | Existing execution role ARN (creates one if null) | `string` | `null` | no |
| task_role_arn | Existing task role ARN (creates one if null) | `string` | `null` | no |
| execution_role_policies | Additional policies for execution role | `list(string)` | `[]` | no |
| task_role_policies | Policies to attach to task role | `list(string)` | `[]` | no |

### Service Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| desired_count | Desired number of tasks (0 for infrastructure-first) | `number` | `0` | no |
| deployment_type | Deployment type: rolling or blue_green | `string` | `"rolling"` | no |
| deployment_minimum_healthy_percent | Minimum healthy percent during deployment | `number` | `100` | no |
| deployment_maximum_percent | Maximum percent during deployment | `number` | `200` | no |
| execute_command_enabled | Enable ECS Exec for debugging | `bool` | `false` | no |
| force_new_deployment | Force a new deployment | `bool` | `false` | no |
| wait_for_steady_state | Wait for service to reach steady state | `bool` | `true` | no |
| health_check_grace_period_seconds | Grace period for LB health checks | `number` | `0` | no |
| ecs_managed_tags_enabled | Enable ECS managed tags | `bool` | `true` | no |
| propagate_tags | Propagate tags from SERVICE or TASK_DEFINITION | `string` | `"SERVICE"` | no |
| platform_version | Fargate platform version | `string` | `"LATEST"` | no |
| capacity_provider_strategies | Capacity provider strategies | `list(object)` | `[]` | no |

### Deployment Circuit Breaker

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| deployment_circuit_breaker | Circuit breaker configuration (enable, rollback) | `object` | `{enable=true, rollback=true}` | no |

### Load Balancer

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| load_balancer_attachment | Load balancer configuration including target group, listener rules, and NLB listener | `object` | `null` | no |

The `load_balancer_attachment` object includes:
- `enabled` - Enable load balancer attachment (default: true)
- `target_group` - Target group configuration (port, protocol, health_check, stickiness)
- `listener_rules` - ALB listener rules with conditions. Each rule accepts an optional `priority` (1-50000); when omitted, AWS automatically assigns the next available priority after the current highest rule on the listener.
- `nlb_listener` - NLB listener configuration (port, protocol, certificate_arn for TLS)
- `container_name` / `container_port` - Override container to attach

### Auto Scaling

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| auto_scaling | Auto scaling configuration | `object` | `null` | no |

The `auto_scaling` object includes:
- `enabled` - Enable auto scaling (default: true)
- `min_capacity` / `max_capacity` - Capacity limits
- `target_tracking` - List of target tracking policies (predefined or custom metrics)
- `scheduled` - List of scheduled scaling actions with cron expressions

### Service Discovery

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| service_discovery | Cloud Map service discovery config | `object` | `null` | no |

The `service_discovery` object includes:
- `namespace_id` - Cloud Map namespace ID
- `dns_record_type` - DNS record type (A or SRV, default: A)
- `dns_ttl` - DNS TTL in seconds (default: 10)
- `routing_policy` - Routing policy (MULTIVALUE or WEIGHTED)
- `health_check_custom_config` - Custom health check configuration

## Outputs

### ECS Service

| Name | Description |
|------|-------------|
| service_id | The ID of the ECS service |
| service_arn | The ARN of the ECS service |
| service_name | The name of the ECS service |
| service_cluster | The cluster ARN where the service is running |

### Task Definition

| Name | Description |
|------|-------------|
| task_definition_arn | The ARN of the task definition |
| task_definition_family | The family of the task definition |
| task_definition_revision | The revision of the task definition |

### IAM Roles

| Name | Description |
|------|-------------|
| execution_role_arn | The ARN of the execution role |
| execution_role_name | The name of the execution role (null if external) |
| task_role_arn | The ARN of the task role |
| task_role_name | The name of the task role (null if external) |

### Security Group

| Name | Description |
|------|-------------|
| security_group_id | The ID of the service security group |
| security_group_arn | The ARN of the service security group |

### Target Groups - Rolling Deployment

| Name | Description |
|------|-------------|
| target_group_arn | Target group ARN (null if LB disabled or blue/green) |
| target_group_arn_suffix | Target group ARN suffix for CloudWatch metrics |
| target_group_name | Target group name |

### Target Groups - Blue/Green Deployment

| Name | Description |
|------|-------------|
| blue_target_group_arn | Blue target group ARN |
| blue_target_group_name | Blue target group name |
| green_target_group_arn | Green target group ARN |
| green_target_group_name | Green target group name |
| target_group_arns | Map of all target group ARNs (primary for rolling, blue/green for blue_green) |

### NLB Listener

| Name | Description |
|------|-------------|
| nlb_listener_arn | NLB listener ARN (null if not using NLB) |

### Auto Scaling

| Name | Description |
|------|-------------|
| autoscaling_target_arn | Application Auto Scaling target ARN |
| autoscaling_policies | Map of scaling policy ARNs |

### Service Discovery

| Name | Description |
|------|-------------|
| service_discovery_arn | Cloud Map service ARN |
| service_discovery_id | Cloud Map service ID |

### Container Information

| Name | Description |
|------|-------------|
| container_name | The name of the primary container |
| container_port | The port of the primary container |

### CloudWatch Logs

| Name | Description |
|------|-------------|
| log_group_name | The name of the CloudWatch log group used by the task |
| log_group_arn | The ARN of the CloudWatch log group used by the task |
| log_stream_prefix | The awslogs stream prefix for the primary container |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              ECS Service                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        Task Definition                                  │  │
│  │  • Container definitions (placeholder)   • CPU/Memory allocation       │  │
│  │  • Execution role                        • Task role                   │  │
│  │  • Network mode (awsvpc)                 • Volumes (EFS/S3/Docker/Host)│  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                          ECS Service                                    │  │
│  │  • Rolling or Blue/Green deployment     • Capacity provider strategy   │  │
│  │  • Network configuration                • Circuit breaker              │  │
│  │  • ECS Exec support                     • Tag propagation              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Security Group     │  │   Target Groups      │  │  Service Discovery │  │
│  │  • VPC CIDR ingress  │  │  • Rolling: 1 TG     │  │  • Cloud Map       │  │
│  │  • Custom CIDRs      │  │  • Blue/Green: 2 TGs │  │  • DNS A/SRV       │  │
│  │  • All egress        │  │  • Health checks     │  │  • Custom health   │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Listener Rules     │  │   Auto Scaling       │  │   IAM Roles        │  │
│  │  • ALB path/host     │  │  • Target tracking   │  │  • Execution role  │  │
│  │  • HTTP headers      │  │  • Scheduled actions │  │  • Task role       │  │
│  │  • NLB listener      │  │  • Custom metrics    │  │  • ECS Exec policy │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    COMPUTE/ECS_SERVICE TERRAFORM MODULE                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │         NETWORK                 │   │          ECS CLUSTER                    │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • vpc_id (required)             │   │ • cluster_arn (required)                │  ║
║  │ • tags                      │   │ • subnet_ids (required)         │   └─────────────────────────────────────────┘  ║
║  └──────────────┬──────────────┘   │ • assign_public_ip              │                                                 ║
║                 │                  │ • security_group_ids            │                                                 ║
║                 │                  │ • allowed_cidr_blocks           │                                                 ║
║                 │                  └─────────────────────────────────┘                                                 ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "compute/ecs_service" }                              │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │ • deployment_controller_type = var.deployment_type == "blue_green" ? "CODE_DEPLOY" : "ECS"                │   │  ║
║  │  │ • placeholder_container_name = "app"                                                                      │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • enable_load_balancer = var.load_balancer_attachment != null && var.load_balancer_attachment.enabled     │   │  ║
║  │  │ • enable_nlb_listener = enable_load_balancer && var.load_balancer_attachment.nlb_listener != null         │   │  ║
║  │  │ • auto_scaling_enabled = var.auto_scaling != null && var.auto_scaling.enabled                              │   │  ║
║  │  │ • enable_service_discovery = var.service_discovery != null                                                │   │  ║
║  │  │ • create_execution_role = var.execution_role_arn == null                                                  │   │  ║
║  │  │ • create_task_role = var.task_role_arn == null                                                            │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │   TASK DEFINITION           │   │       SERVICE CONFIG            │   │        DEPLOYMENT                       │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • task_cpu                  │   │ • desired_count                 │   │ • deployment_type (rolling/blue_green)  │  ║
║  │ • task_memory               │   │ • execute_command_enabled        │   │ • deployment_minimum_healthy_percent    │  ║
║  │ • container_port            │   │ • force_new_deployment          │   │ • deployment_maximum_percent            │  ║
║  │ • launch_type               │   │ • wait_for_steady_state         │   │ • deployment_circuit_breaker            │  ║
║  │ • network_mode              │   │ • platform_version              │   └─────────────────────────────────────────┘  ║
║  │ • requires_compatibilities  │   │ • capacity_provider_strategies  │                                                ║
║  │ • runtime_platform          │   │ • health_check_grace_period_    │                                                ║
║  │ • volumes[]                 │   │   seconds                       │                                                ║
║  └─────────────────────────────┘   └─────────────────────────────────┘                                                ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐                                                ║
║  │          IAM                │   │       SECURITY                  │                                                ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤                                                ║
║  │ • execution_role_arn        │   │ • security_group_ids            │                                                ║
║  │ • task_role_arn             │   │ • allowed_cidr_blocks           │                                                ║
║  │ • execution_role_policies[] │   └─────────────────────────────────┘                                                ║
║  │ • task_role_policies[]      │                                                                                      ║
║  └─────────────────────────────┘                                                                                      ║
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                      LOAD BALANCER ATTACHMENT                                                     │  ║
║  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │ • load_balancer_attachment:                                                                                      │  ║
║  │   - enabled                     │ - target_group: port, protocol, target_type, deregistration_delay,             │  ║
║  │   - container_name/port         │               health_check{}, stickiness{}                                     │  ║
║  │   - listener_rules[]: listener_arn, priority (optional), conditions[], weight                                     │  ║
║  │   - nlb_listener: nlb_arn, port, protocol, certificate_arn, ssl_policy, alpn_policy                              │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐                                                ║
║  │     AUTO SCALING            │   │     SERVICE DISCOVERY           │                                                ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤                                                ║
║  │ • auto_scaling:             │   │ • service_discovery:            │                                                ║
║  │   - enabled                 │   │   - namespace_id                │                                                ║
║  │   - min_capacity            │   │   - dns_record_type (A/SRV)     │                                                ║
║  │   - max_capacity            │   │   - dns_ttl                     │                                                ║
║  │   - target_tracking[]:      │   │   - routing_policy              │                                                ║
║  │     · policy_name           │   │   - health_check_custom_config  │                                                ║
║  │     · target_value          │   └─────────────────────────────────┘                                                ║
║  │     · predefined_metric     │                                                                                      ║
║  │     · custom_metric{}       │                                                                                      ║
║  │     · scale_in/out_cooldown │                                                                                      ║
║  │     · scale_in_enabled      │                                                                                      ║
║  │   - scheduled[]:            │                                                                                      ║
║  │     · name, schedule (cron) │                                                                                      ║
║  │     · min/max_capacity      │                                                                                      ║
║  │     · timezone, start/end   │                                                                                      ║
║  └─────────────────────────────┘                                                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    IAM ROLES & POLICIES                                                      │    ║
║    │                       (conditional: create_execution_role / create_task_role)                                │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │  aws_iam_role.execution[0]              │  aws_iam_role.task[0]                                             │    ║
║    │  aws_iam_role_policy_attachment         │  aws_iam_role_policy.task_exec_command[0]                         │    ║
║    │    .execution_base[0]                   │  aws_iam_role_policy_attachment.task_additional                   │    ║
║    │  aws_iam_role_policy.execution_secrets  │                                                                    │    ║
║    │  aws_iam_role_policy_attachment         │                                                                    │    ║
║    │    .execution_additional                │                                                                    │    ║
║    └──────────────────────────────────────────────────────────────────────┬──────────────────────────────────────┘    ║
║                                                                           │                                            ║
║                                                                           ▼                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    aws_ecs_task_definition.this                                             │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ Configures: family, CPU, memory, network mode, container definitions (placeholder),                         │    ║
║    │             execution_role_arn, task_role_arn, runtime_platform, volumes (EFS/S3/Docker/Host)               │    ║
║    │ Lifecycle: ignore_changes = all (external deployment controller manages updates)                            │    ║
║    └──────────────────────────────────────────────────────────────────────┬──────────────────────────────────────┘    ║
║                                                                           │                                            ║
║                   ┌───────────────────────────────────────────────────────┼───────────────────────────────────┐        ║
║                   │                                                       │                                   │        ║
║                   ▼                                                       ▼                                   ▼        ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────────────────────────────────────────────────┐   ║
║    │  module.security_group       │    │                         aws_ecs_service.this                             │   ║
║    │  (networking/security-groups)│    │                             (CORE RESOURCE)                              │   ║
║    ├──────────────────────────────┤    ├──────────────────────────────────────────────────────────────────────────┤   ║
║    │ • VPC CIDR ingress on        │    │  ┌──────────────────┐  ┌───────────────────┐  ┌───────────────────────┐  │   ║
║    │   container port             │    │  │network_configuration│ │ load_balancer     │  │ service_registries   │  │   ║
║    │ • Custom CIDR ingress        │    │  │   (dynamic)      │  │    (dynamic)      │  │     (dynamic)        │  │   ║
║    │ • All egress                 │    │  └──────────────────┘  └───────────────────┘  └───────────────────────┘  │   ║
║    └──────────────────────────────┘    │                                                                          │   ║
║                                        │  ┌──────────────────┐  ┌───────────────────┐                             │   ║
║                                        │  │deployment_circuit │  │capacity_provider_ │                             │   ║
║                                        │  │  _breaker(dynamic)│  │ strategy (dynamic)│                             │   ║
║                                        │  └──────────────────┘  └───────────────────┘                             │   ║
║                                        │                                                                          │   ║
║                                        │  deployment_controller.type = ECS | CODE_DEPLOY                          │   ║
║                                        └────────────────────────────────────┬─────────────────────────────────────┘   ║
║                                                                             │                                          ║
║           ┌─────────────────────────────────────────┬───────────────────────┼───────────────────────┬───────────────┐  ║
║           │                                         │                       │                       │               │  ║
║           ▼                                         ▼                       ▼                       ▼               ▼  ║
║    ┌───────────────────────┐    ┌───────────────────────────────┐    ┌──────────────────┐   ┌────────────────────────┐ ║
║    │  TARGET GROUPS        │    │  aws_lb_listener_rule.alb     │    │ aws_lb_listener  │   │aws_service_discovery   │ ║
║    │  (conditional)        │    │  (for_each: listener_rules)   │    │   .nlb[0]        │   │  _service.this[0]      │ ║
║    ├───────────────────────┤    ├───────────────────────────────┤    │  (count: 0 or 1) │   │(count: 0 or 1)         │ ║
║    │ Rolling:              │    │ • path-pattern condition      │    ├──────────────────┤   ├────────────────────────┤ ║
║    │  aws_lb_target_group  │    │ • host-header condition       │    │ • TCP/TLS/UDP    │   │ • Cloud Map DNS        │ ║
║    │   .this[0]            │    │ • http-header condition       │    │ • Certificate    │   │ • A or SRV records     │ ║
║    │                       │    │ • query-string condition      │    │ • SSL policy     │   │ • Custom health check  │ ║
║    │ Blue/Green:           │    │ • source-ip condition         │    └──────────────────┘   └────────────────────────┘ ║
║    │  aws_lb_target_group  │    │ lifecycle: ignore action      │                                                      ║
║    │   .tg_1[0] (blue)     │    │  (external controller swaps)  │                                                      ║
║    │  aws_lb_target_group  │    └───────────────────────────────┘                                                      ║
║    │   .tg_2[0] (green)    │                                                                                           ║
║    └───────────────────────┘                                                                                           ║
║                                                                                                                        ║
║                   ┌─────────────────────────────────────────────────────────────────────────────────────┐              ║
║                   │                              AUTO SCALING RESOURCES                                  │              ║
║                   │                         (conditional: auto_scaling_enabled)                           │              ║
║                   ├─────────────────────────────────────────────────────────────────────────────────────┤              ║
║                   │                                                                                      │              ║
║                   │  aws_appautoscaling_target.this[0]                                                   │              ║
║                   │        │                                                                             │              ║
║                   │        ├──────────────────────────────────────────────────┐                          │              ║
║                   │        │                                                  │                          │              ║
║                   │        ▼                                                  ▼                          │              ║
║                   │  aws_appautoscaling_policy.target_tracking         aws_appautoscaling_scheduled      │              ║
║                   │        (for_each)                                   _action.this (for_each)          │              ║
║                   │  • ECSServiceAverageCPUUtilization                • Cron-based scheduling            │              ║
║                   │  • ECSServiceAverageMemoryUtilization             • Time zone support                │              ║
║                   │  • ALBRequestCountPerTarget                       • Min/max capacity adjustment      │              ║
║                   │  • Custom CloudWatch metrics                                                         │              ║
║                   └─────────────────────────────────────────────────────────────────────────────────────┘              ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │           ECS SERVICE                   │   │          TASK DEFINITION                │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • service_id                            │   │ • task_definition_arn                   │                            ║
║  │ • service_arn                           │   │ • task_definition_family                │                            ║
║  │ • service_name                          │   │ • task_definition_revision              │                            ║
║  │ • service_cluster                       │   └─────────────────────────────────────────┘                            ║
║  └─────────────────────────────────────────┘                                                                          ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │            IAM ROLES                    │   │          SECURITY GROUP                 │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • execution_role_arn                    │   │ • security_group_id                     │                            ║
║  │ • execution_role_name                   │   │ • security_group_arn                    │                            ║
║  │ • task_role_arn                         │   └─────────────────────────────────────────┘                            ║
║  │ • task_role_name                        │                                                                          ║
║  └─────────────────────────────────────────┘                                                                          ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │      TARGET GROUPS (Rolling)            │   │    TARGET GROUPS (Blue/Green)          │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • target_group_arn                      │   │ • blue_target_group_arn                 │                            ║
║  │ • target_group_arn_suffix               │   │ • blue_target_group_name                │                            ║
║  │ • target_group_name                     │   │ • green_target_group_arn                │                            ║
║  └─────────────────────────────────────────┘   │ • green_target_group_name               │                            ║
║                                                │ • target_group_arns (map)               │                            ║
║                                                └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │          AUTO SCALING                   │   │        SERVICE DISCOVERY                │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • autoscaling_target_arn                │   │ • service_discovery_arn                 │                            ║
║  │ • autoscaling_policies (map)            │   │ • service_discovery_id                  │                            ║
║  └─────────────────────────────────────────┘   └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         CONTAINER INFO                  │   │         NLB LISTENER                    │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • container_name                        │   │ • nlb_listener_arn                      │                            ║
║  │ • container_port                        │   └─────────────────────────────────────────┘                            ║
║  └─────────────────────────────────────────┘                                                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              DATA FLOW DIAGRAM                                                         ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║                              ┌────────────────────────────────────────────┐                                            ║
║                              │    var.execution_role_arn (null = create)  │                                            ║
║                              │    var.task_role_arn (null = create)       │                                            ║
║                              └───────────────────┬────────────────────────┘                                            ║
║                                                  │                                                                     ║
║                                                  ▼                                                                     ║
║  var.execution_role_policies ───► aws_iam_role.execution[0] ◄─── var.execute_command_enabled                           ║
║  var.task_role_policies ────────► aws_iam_role.task[0] ◄──────── var.execute_command_enabled                           ║
║                                                  │                                                                     ║
║                                                  ▼                                                                     ║
║  var.task_cpu ─────────────────────────────────────────────────────────────┐                                           ║
║  var.task_memory ──────────────────────────────────────────────────────────┤                                           ║
║  var.container_port ───────────────────────────────────────────────────────┤                                           ║
║  var.network_mode ─────────────────────────────────────────────────────────┤                                           ║
║  var.runtime_platform ─────────────────────────────────────────────────────┤                                           ║
║  var.volumes ──────────────────────────────────────────────────────────────┤                                           ║
║                                                                            ▼                                           ║
║                                              ┌───────────────────────────────────────┐                                 ║
║                                              │    aws_ecs_task_definition.this       │                                 ║
║                                              └───────────────────┬───────────────────┘                                 ║
║                                                                  │                                                     ║
║  var.vpc_id ───────────────────────────────────────────────────────────────────────────────────────────┐               ║
║  var.subnet_ids ───────────────────────────────────────────────────────────────────────────────────────┤               ║
║  var.assign_public_ip ─────────────────────────────────────────────────────────────────────────────────┤               ║
║  var.allowed_cidr_blocks ──────────► module.security_group ────────────────────────────────────────────┤               ║
║  var.security_group_ids ───────────────────────────────────────────────────────────────────────────────┤               ║
║                                                                                                        │               ║
║  var.cluster_arn ──────────────────────────────────────────────────────────────────────────────────────┤               ║
║  var.desired_count ────────────────────────────────────────────────────────────────────────────────────┤               ║
║  var.deployment_type ──────────────────────────────────────────────────────────────────────────────────┤               ║
║  var.deployment_circuit_breaker ───────────────────────────────────────────────────────────────────────┤               ║
║  var.capacity_provider_strategies ─────────────────────────────────────────────────────────────────────┤               ║
║                                                                                                        ▼               ║
║                              ┌───────────────────────────────────────────────────────────────────────────┐             ║
║                              │                        aws_ecs_service.this                               │             ║
║                              └────────────────────────────────────┬──────────────────────────────────────┘             ║
║                                                                   │                                                    ║
║           ┌─────────────────────┬─────────────────────┬───────────┴────────┬──────────────────┬──────────────────┐     ║
║           │                     │                     │                    │                  │                  │     ║
║           ▼                     ▼                     ▼                    ▼                  ▼                  ▼     ║
║  var.load_balancer_     var.load_balancer_    var.load_balancer_   var.auto_scaling   var.service_   (ECS Tasks)     ║
║    attachment           attachment            attachment                               discovery                      ║
║    .target_group        .listener_rules       .nlb_listener                                                           ║
║           │                     │                     │                    │                  │                       ║
║           ▼                     ▼                     ▼                    ▼                  ▼                       ║
║  aws_lb_target_group    aws_lb_listener_rule  aws_lb_listener     aws_appautoscaling_  aws_service_discovery_        ║
║  .this[0] / .tg_1[0]    .alb (for_each)       .nlb[0]             target.this[0]       service.this[0]               ║
║  / .tg_2[0]                                                              │                                            ║
║                                                                          │                                            ║
║                              ┌───────────────────────────────────────────┴───────────────────────────┐                 ║
║                              │                                                                       │                 ║
║                              ▼                                                                       ▼                 ║
║  var.auto_scaling.target_tracking ──► aws_appautoscaling_policy.target_tracking                     │                 ║
║  var.auto_scaling.scheduled ────────► aws_appautoscaling_scheduled_action.this                      │                 ║
║                                                                                                      │                 ║
║                                                                                                      ▼                 ║
║                                                                                               MODULE OUTPUTS           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_iam_role.execution` | 0 or 1 | Task execution role (pulls images, writes logs) |
| `aws_iam_role.task` | 0 or 1 | Task role (application permissions) |
| `aws_iam_role_policy_attachment` | varies | Policy attachments for roles |
| `aws_ecs_task_definition` | 1 | Container configuration (placeholder) |
| `aws_ecs_service` | 1 | Core ECS service resource |
| `module.security_group` | 1 | Security group for tasks |
| `aws_lb_target_group.this` | 0 or 1 | Target group for rolling deployment |
| `aws_lb_target_group.tg_1` | 0 or 1 | Blue target group for blue/green |
| `aws_lb_target_group.tg_2` | 0 or 1 | Green target group for blue/green |
| `aws_lb_listener_rule.alb` | for_each | ALB listener rules |
| `aws_lb_listener.nlb` | 0 or 1 | NLB listener |
| `aws_service_discovery_service` | 0 or 1 | Cloud Map service |
| `aws_appautoscaling_target` | 0 or 1 | Auto scaling target |
| `aws_appautoscaling_policy.target_tracking` | for_each | Target tracking policies |
| `aws_appautoscaling_scheduled_action` | for_each | Scheduled scaling actions |

## FAQ

### What is the placeholder container and why is it used?

The module deploys `public.ecr.aws/docker/library/hello-world:latest` as a placeholder container. This enables an **infrastructure-first provisioning workflow**:

1. **Provision Infrastructure**: Terraform creates the ECS service, target groups, auto scaling, etc.
2. **Configure External Deployment Controller**: Use module outputs to set up the external deployment controller (e.g. CodeDeploy application and deployment group)
3. **Deploy Application**: The external controller updates the task definition with your actual application

The placeholder container prints a message and exits, so load balancer health checks will fail until the actual application is deployed. This is expected behavior.

### When should I use rolling vs blue/green deployment?

| Feature | Rolling (ECS) | Blue/Green (external controller) |
|---------|--------------|----------------------------------|
| **Complexity** | Simple | More complex (requires an external deployment controller) |
| **Rollback** | Automatic via circuit breaker | Instant traffic switch |
| **Traffic shift** | Gradual (min/max healthy %) | All-at-once or gradual |
| **Testing** | No pre-production testing | Test green before switching |
| **Infrastructure** | 1 target group | 2 target groups |

**Use rolling when:**
- Simple deployments with automatic rollback are sufficient
- You want minimal infrastructure complexity
- Built-in ECS deployment features meet your needs

**Use blue/green when:**
- You need instant rollback capability
- You want to test in production before switching traffic
- You need advanced deployment strategies (canary, linear)

### How do I use this module with an NLB instead of an ALB?

For NLB, configure the `nlb_listener` instead of `listener_rules`:

```hcl
load_balancer_attachment = {
  target_group = {
    port     = 5000
    protocol = "TCP"  # or "TLS", "UDP", "TCP_UDP"
  }
  # No listener_rules for NLB
  nlb_listener = {
    nlb_arn         = aws_lb.nlb.arn
    port            = 5000
    protocol        = "TCP"
    # For TLS:
    # certificate_arn = "arn:aws:acm:..."
    # ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  }
}
```

### Can I use both ALB listener rules and NLB listener?

No, each ECS service can only be attached to one load balancer. Use either:
- `listener_rules` for ALB (path/host-based routing)
- `nlb_listener` for NLB (TCP/TLS/UDP)

### How does auto scaling work with the predefined metrics?

The module supports these predefined ECS metrics:

| Metric | Description |
|--------|-------------|
| `ECSServiceAverageCPUUtilization` | Average CPU utilization across all tasks |
| `ECSServiceAverageMemoryUtilization` | Average memory utilization across all tasks |
| `ALBRequestCountPerTarget` | Average request count per target (requires load balancer) |

Example with multiple target tracking policies:

```hcl
auto_scaling = {
  min_capacity = 2
  max_capacity = 100

  target_tracking = [
    {
      policy_name       = "cpu-utilization"
      target_value      = 70
      predefined_metric = "ECSServiceAverageCPUUtilization"
    },
    {
      policy_name       = "request-count"
      target_value      = 1000
      predefined_metric = "ALBRequestCountPerTarget"
    }
  ]
}
```

### How do I attach EFS volumes to my tasks?

Configure the `volumes` variable with EFS configuration:

```hcl
volumes = [
  {
    name = "my-efs-volume"
    efs_volume_configuration = {
      file_system_id     = "fs-12345678"
      root_directory     = "/app-data"
      transit_encryption = "ENABLED"
      authorization_config = {
        access_point_id = "fsap-12345678"
        iam             = "ENABLED"
      }
    }
  }
]
```

Note: The placeholder task definition does not mount volumes. Your application task definition (deployed by the external controller) should include the volume mounts.

### How do I attach S3 Files volumes to my tasks?

Configure the `volumes` variable with an S3 Files configuration:

```hcl
volumes = [
  {
    name = "my-s3files-volume"
    s3files_volume_configuration = {
      file_system_arn         = "arn:aws:s3files:us-east-1:123456789012:file-system/fs-12345678"
      root_directory          = "/"
      access_point_arn        = "arn:aws:s3files:us-east-1:123456789012:file-system/fs-12345678/access-point/fsap-12345678"
      transit_encryption_port = 2999
    }
  }
]
```

The task definition must include a task IAM role with the permissions required to attach the S3 Files file system to ECS tasks. If `task_role_arn` is null, attach the required permissions with `task_role_policies` or `task_role_inline_policies`.

### How do I attach an EC2 host path to my tasks?

Configure the `volumes` variable with a `host_path`. Host path volumes are supported only for EC2-compatible ECS tasks.

```hcl
launch_type              = "EC2"
requires_compatibilities = ["EC2"]

volumes = [
  {
    name      = "host-data"
    host_path = "/var/lib/app-data"
  }
]
```

Mount the named volume from your deployed application task definition using a container mount point. Data remains on the EC2 container instance path and does not move with the task if ECS places a replacement task on another instance.

### How do I enable ECS Exec for debugging?

Set `execute_command_enabled = true`. This will:

1. Add necessary IAM permissions to the task role
2. Enable execute command on the ECS service

Then use the AWS CLI to connect:

```bash
aws ecs execute-command \
  --cluster my-cluster \
  --task <task-id> \
  --container app \
  --interactive \
  --command "/bin/sh"
```

### What listener rule conditions are supported?

The module supports all ALB listener rule conditions:

| Condition Type | Description | Example |
|---------------|-------------|---------|
| `path-pattern` | URL path pattern | `["/api/*", "/v1/*"]` |
| `host-header` | Host header values | `["api.example.com"]` |
| `http-header` | HTTP header name and values | `["X-Custom-Header", "value1", "value2"]` |
| `http-request-method` | HTTP methods | `["GET", "POST"]` |
| `query-string` | Query string parameters | `["key", "value"]` |
| `source-ip` | Source IP CIDR blocks | `["10.0.0.0/8"]` |

### How do I use capacity providers instead of launch type?

Use `capacity_provider_strategies` instead of relying on `launch_type`:

```hcl
capacity_provider_strategies = [
  {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 2  # Always keep 2 tasks on Fargate
  },
  {
    capacity_provider = "FARGATE_SPOT"
    weight            = 4  # 4:1 ratio of Spot to On-Demand
  }
]
```

When `capacity_provider_strategies` is set, `launch_type` is ignored.

## Deployment Workflow

This module is designed for an infrastructure-first provisioning workflow:

1. **Provision Infrastructure**: This module creates the ECS service with a placeholder container
2. **Configure External Deployment Controller**: Use the module outputs to set up your external deployment controller (e.g. CodeDeploy application and deployment group)
3. **Deploy Application**: The external controller updates the task definition with the actual application container

### Placeholder Container

The module deploys the hello-world container (`public.ecr.aws/docker/library/hello-world:latest`) as a placeholder. This container prints a message and exits, so:
- Load balancer health checks will fail until the actual application is deployed
- This is expected behavior for infrastructure-first provisioning
- The external deployment controller should deploy the actual application immediately after infrastructure is ready

## Deployment Strategies

### Rolling Deployment (Default)

Uses the ECS deployment controller for zero-downtime rolling updates:
- Configurable minimum/maximum healthy percent
- Built-in circuit breaker with optional rollback
- Simple and fully managed by ECS

### Blue/Green Deployment

Sets up infrastructure for blue/green deployments managed by an external controller:
- Creates two target groups (tg-1 and tg-2)
- Sets deployment controller to CODE_DEPLOY
- Outputs all ARNs needed to wire up the external controller
- The external deployment controller (application, deployment group, etc.) must be managed outside of this module

## Notes

- The module creates a security group that allows inbound traffic from the VPC CIDR on the container port
- For Fargate tasks in public subnets without NAT, set `assign_public_ip = true`
- The placeholder container uses hello-world from public ECR - no special permissions needed
- For blue/green deployments, the module only creates the infrastructure; the external deployment controller must be configured separately
- The task definition has `lifecycle { ignore_changes = all }` since the external deployment controller manages updates
- Listener rules have `lifecycle { ignore_changes = [action] }` for blue/green deployments where the external controller switches target groups
- When using `ALBRequestCountPerTarget` metric for auto scaling, a load balancer must be configured
- The `desired_count` defaults to 0 for infrastructure-first provisioning; the external controller will manage the actual count
- Target group names are truncated to meet AWS naming requirements (max 32 characters)
