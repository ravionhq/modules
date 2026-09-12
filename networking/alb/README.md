# Application Load Balancer Module

This module creates an AWS Application Load Balancer (ALB) with HTTP and HTTPS listeners, security group, optional access logging, and WAF integration.

## Features

- Application Load Balancer with configurable settings (internal/external, HTTP/2, idle timeout)
- HTTP and HTTPS listeners with configurable ports and default actions
- Automatic HTTP to HTTPS redirect when both listeners are enabled
- Security group with IPv4 and IPv6 ingress rules
- Optional S3 bucket for access logs with lifecycle policies and encryption
- WAFv2 Web ACL association support
- SNI support with additional SSL certificates
- TLS 1.3 support with modern SSL policies
- Security hardening (invalid header dropping, desync mitigation)

## Usage

### Basic ALB (HTTP Only)

```hcl
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  tags = {
    Environment = "production"
  }
}
```

### ALB with HTTPS

To enable HTTPS, you must set `https_listener_enabled = true` and provide `certificate_arns`. The first ARN in the list is used as the default certificate; any additional ARNs are attached for SNI:

```hcl
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  https_listener_enabled = true
  certificate_arns      = [aws_acm_certificate.main.arn]

  tags = {
    Environment = "production"
  }
}
```

### Internal ALB with HTTPS

```hcl
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "internal"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  internal_load_balancer_enabled   = true

  https_listener_enabled = true
  certificate_arns      = [aws_acm_certificate.internal.arn]
}
```

### With Access Logs and WAF

```hcl
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "secure"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  https_listener_enabled = true
  certificate_arns      = [aws_acm_certificate.main.arn]

  # Access Logs - creates S3 bucket automatically
  access_logs_enabled         = true
  access_logs_retention_days = 365

  # WAF
  waf_association_enabled = true
  web_acl_arn            = aws_wafv2_web_acl.main.arn

  # Custom default response
  default_action_status_code = 404
  default_action_message     = "Not Found"
}
```

### Integration with ECS Service

```hcl
# Create ALB with HTTPS
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  https_listener_enabled = true
  certificate_arns      = [aws_acm_certificate.main.arn]
}

# ECS service creates its own target group and listener rule
module "api_service" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ecs?ref=v1.0.0"

  name       = "api"
  cluster_id = module.ecs_cluster.id

  # ALB integration - ECS module creates target group and listener rule
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  listener_rule_priority = 100
  listener_rule_conditions = {
    path_patterns = ["/api/*"]
  }

  target_group_port = 8080
  health_check = {
    path = "/health"
  }
}

# Another ECS service on the same ALB
module "web_service" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ecs?ref=v1.0.0"

  name       = "web"
  cluster_id = module.ecs_cluster.id

  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  listener_rule_priority = 200
  listener_rule_conditions = {
    path_patterns = ["/*"]
  }

  target_group_port = 3000
  health_check = {
    path = "/"
  }
}
```

### Integration with EKS (TargetGroupBinding)

For EKS, the ECS-style integration won't work directly. Instead, use the AWS Load Balancer Controller's `TargetGroupBinding` resource in Kubernetes to register pods with a target group created outside of Kubernetes.

```hcl
# Create ALB with HTTPS
module "alb" {
  source = "git::https://github.com/ravionhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "eks-alb"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  https_listener_enabled = true
  certificate_arns      = [aws_acm_certificate.main.arn]
}

# Create target group for EKS service
resource "aws_lb_target_group" "eks_api" {
  name        = "eks-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }
}

# Create listener rule
resource "aws_lb_listener_rule" "eks_api" {
  listener_arn = module.alb.https_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Output for Kubernetes TargetGroupBinding
output "eks_api_target_group_arn" {
  value = aws_lb_target_group.eks_api.arn
}
```

Then in Kubernetes:

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: api-tgb
spec:
  serviceRef:
    name: api-service
    port: 8080
  targetGroupARN: <output from terraform>
  targetType: ip
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
| name | Name prefix for all resources created by this module | `string` | n/a | yes |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |

### Network

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_id | The ID of the VPC where the ALB will be created | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the ALB (minimum 2 for HA) | `list(string)` | n/a | yes |

### ALB Settings

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| internal_load_balancer_enabled | If true, the ALB will be internal (not internet-facing) | `bool` | `false` | no |
| deletion_protection_enabled | If true, the resource cannot be deleted via the AWS API until this is set to false | `bool` | `true` | no |
| idle_timeout | The time in seconds that the connection is allowed to be idle (1-4000) | `number` | `60` | no |
| http2_enabled | Enable HTTP/2 on the ALB | `bool` | `true` | no |
| invalid_header_drop_enabled | Drop HTTP headers with invalid header fields | `bool` | `true` | no |
| desync_mitigation_mode | How the ALB handles HTTP desync requests (monitor/defensive/strictest) | `string` | `"defensive"` | no |
| host_header_preservation_enabled | Preserve the Host header in the HTTP request | `bool` | `false` | no |
| xff_header_processing_mode | How the ALB modifies the X-Forwarded-For header (append/preserve/remove) | `string` | `"append"` | no |
| waf_fail_open_enabled | Allow traffic when WAF is unavailable | `bool` | `false` | no |

### Listeners

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| http_listener_enabled | Create an HTTP listener on port 80 | `bool` | `true` | no |
| https_listener_enabled | Create an HTTPS listener on port 443 (requires certificate_arns) | `bool` | `false` | no |
| http_listener_port | The port for the HTTP listener | `number` | `80` | no |
| https_listener_port | The port for the HTTPS listener | `number` | `443` | no |
| http_to_https_redirect_enabled | Redirect HTTP traffic to HTTPS (when both listeners enabled) | `bool` | `true` | no |

### SSL/TLS

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| certificate_arns | ACM certificate ARNs for the HTTPS listener. The first ARN is the default certificate; additional ARNs are attached for SNI | `list(string)` | `[]` | no |
| ssl_policy | The SSL policy for the HTTPS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |

### Default Action

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| default_action_status_code | HTTP status code when no listener rule matches (200-599) | `number` | `503` | no |
| default_action_content_type | Content type for the fixed response | `string` | `"text/plain"` | no |
| default_action_message | Message body for the fixed response (max 1024 chars) | `string` | `"Service Unavailable"` | no |

### Security Group

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ingress_cidr_blocks | IPv4 CIDR blocks allowed to access the ALB | `list(string)` | `["0.0.0.0/0"]` | no |
| ingress_ipv6_cidr_blocks | IPv6 CIDR blocks allowed to access the ALB | `list(string)` | `["::/0"]` | no |
| ingress_security_group_ids | Security group IDs whose members are allowed to access the ALB | `list(string)` | `[]` | no |

### Access Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| access_logs_enabled | Enable access logging for the ALB | `bool` | `false` | no |
| access_logs_bucket_arn | Existing S3 bucket ARN for access logs (creates new if null) | `string` | `null` | no |
| access_logs_prefix | S3 prefix for access logs | `string` | `""` | no |
| access_logs_retention_days | Days to retain access logs in S3 | `number` | `90` | no |
| access_logs_kms_key_id | KMS key ID for S3 bucket encryption (uses AES256 if null) | `string` | `null` | no |
| access_logs_versioning_enabled | Enable versioning for the access logs S3 bucket | `bool` | `false` | no |

### WAF

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| waf_association_enabled | Whether to associate a WAF Web ACL with the ALB | `bool` | `false` | no |
| web_acl_arn | The ARN of a WAFv2 Web ACL to associate with the ALB | `string` | `null` | no |

## Outputs

### Application Load Balancer

| Name | Description |
|------|-------------|
| alb_id | The ID of the Application Load Balancer |
| alb_arn | The ARN of the Application Load Balancer |
| alb_arn_suffix | The ARN suffix of the ALB for use with CloudWatch Metrics |
| alb_dns_name | The DNS name of the Application Load Balancer |
| alb_zone_id | The canonical hosted zone ID of the ALB (for Route53 alias records) |

### Listeners

| Name | Description |
|------|-------------|
| http_listener_arn | The ARN of the HTTP listener (null if disabled) |
| https_listener_arn | The ARN of the HTTPS listener (null if disabled) |

### Security Group

| Name | Description |
|------|-------------|
| security_group_id | The ID of the ALB security group |
| security_group_arn | The ARN of the ALB security group |

### Access Logs

| Name | Description |
|------|-------------|
| access_logs_bucket_name | The name of the S3 bucket for access logs (null if disabled or using existing) |
| access_logs_bucket_arn | The ARN of the S3 bucket for access logs (null if disabled or using existing) |

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Application Load Balancer                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                              ALB Core                                   │  │
│  │  • Internet-facing or Internal     • HTTP/2 support                    │  │
│  │  • Idle timeout configuration      • Desync mitigation                 │  │
│  │  • Header field validation         • X-Forwarded-For handling          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   HTTP Listener      │  │   HTTPS Listener     │  │   Security Group   │  │
│  │  • Port 80           │  │  • Port 443          │  │  • IPv4/IPv6       │  │
│  │  • Redirect to HTTPS │  │  • TLS 1.2/1.3       │  │  • HTTP/HTTPS      │  │
│  │  • Fixed response    │  │  • SNI certificates  │  │  • All egress      │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────────────────────────────┐  │
│  │   Access Logs        │  │                WAF Integration               │  │
│  │  • S3 bucket         │  │  • WAFv2 Web ACL association                 │  │
│  │  • Lifecycle rules   │  │  • Fail-open configuration                   │  │
│  │  • Encryption        │  │                                              │  │
│  └──────────────────────┘  └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       NETWORKING/ALB TERRAFORM MODULE                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │         NETWORK                 │   │          ALB SETTINGS                   │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • vpc_id (required)             │   │ • internal_load_balancer_enabled                              │  ║
║  │ • tags                      │   │ • subnet_ids (required, min 2)  │   │ • deletion_protection_enabled                   │  ║
║  └──────────────┬──────────────┘   └─────────────────────────────────┘   │ • idle_timeout                          │  ║
║                 │                                                         │ • http2_enabled                          │  ║
║                 │                                                         │ • invalid_header_drop_enabled            │  ║
║                 │                                                         │ • desync_mitigation_mode                │  ║
║                 │                                                         │ • host_header_preservation_enabled                  │  ║
║                 │                                                         │ • xff_header_processing_mode            │  ║
║                 │                                                         │ • waf_fail_open_enabled                  │  ║
║                 │                                                         └─────────────────────────────────────────┘  ║
║                 ▼                                                                                                      ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                               LOCALS                                                              │  ║
║  │  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ • default_tags = { ManagedBy = "terraform", Module = "networking/alb" }                                   │   │  ║
║  │  │ • tags = merge(default_tags, var.tags)                                                                    │   │  ║
║  │  │                                                                                                            │   │  ║
║  │  │ FEATURE FLAGS:                                                                                             │   │  ║
║  │  │ • create_access_logs_bucket = var.access_logs_enabled && var.access_logs_bucket_arn == null                │   │  ║
║  │  │ • access_logs_bucket_name = create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : extracted_name  │   │  ║
║  │  │ • create_http_listener = var.http_listener_enabled                                                         │   │  ║
║  │  │ • create_https_listener = var.https_listener_enabled                                                       │   │  ║
║  │  └───────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │      LISTENERS              │   │         SSL/TLS                 │   │       DEFAULT ACTION                    │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • http_listener_enabled      │   │ • certificate_arns              │   │ • default_action_status_code            │  ║
║  │ • https_listener_enabled     │   │ • ssl_policy                    │   │ • default_action_content_type           │  ║
║  │ • http_listener_port        │   │                                 │   │ • default_action_message                │  ║
║  │ • https_listener_port       │   └─────────────────────────────────┘   └─────────────────────────────────────────┘  ║
║  │ • http_to_https_redirect_enabled    │                                                                                       ║
║  └─────────────────────────────┘                                                                                       ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │    SECURITY GROUP           │   │        ACCESS LOGS              │   │            WAF                          │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • ingress_cidr_blocks       │   │ • access_logs_enabled            │   │ • waf_association_enabled                │  ║
║  │ • ingress_ipv6_cidr_blocks  │   │ • access_logs_bucket_arn        │   │ • web_acl_arn                           │  ║
║  └─────────────────────────────┘   │ • access_logs_prefix            │   └─────────────────────────────────────────┘  ║
║                                    │ • access_logs_retention_days    │                                                 ║
║                                    │ • access_logs_kms_key_id        │                                                 ║
║                                    │ • access_logs_versioning_enabled│                                                 ║
║                                    └─────────────────────────────────┘                                                 ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │                                        DATA SOURCES                                                               │  ║
║  │  • data.aws_caller_identity.current    - Account ID for bucket naming and policies                               │  ║
║  │  • data.aws_region.current             - Current region                                                           │  ║
║  │  • data.aws_elb_service_account.current - ELB service account for bucket policy                                  │  ║
║  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                      module.security_group                                                   │    ║
║    │                              (uses ../security-groups module)                                                │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ Configures: VPC security group with HTTP/HTTPS ingress rules (IPv4 + IPv6), all egress allowed              │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                         aws_lb.this                                                          │    ║
║    │                                        (CORE RESOURCE)                                                       │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  Attributes:                                                                                                 │    ║
║    │  • name, internal_load_balancer_enabled, load_balancer_type = "application"                                                        │    ║
║    │  • security_groups = [module.security_group.security_group_id]                                               │    ║
║    │  • subnets, idle_timeout, http2_enabled, invalid_header_drop_enabled                                           │    ║
║    │  • desync_mitigation_mode, host_header_preservation_enabled, xff_header_processing_mode                                  │    ║
║    │  • waf_fail_open_enabled, deletion_protection_enabled                                                                 │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────────────────┐                                                                             │    ║
║    │  │ dynamic "access_logs" {...} │  (enabled when var.access_logs_enabled = true)                               │    ║
║    │  └─────────────────────────────┘                                                                             │    ║
║    │                                                                                                              │    ║
║    │  lifecycle { precondition: certificate_arns required when HTTPS enabled }                                    │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────┐                    ║
║           │                                               │                                       │                    ║
║           ▼                                               ▼                                       ▼                    ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │  aws_lb_listener.http[0]    │    │  aws_lb_listener.https[0]   │    │  aws_lb_listener_certificate │          ║
║    │      (count: 0 or 1)        │    │      (count: 0 or 1)        │    │    .additional (for_each)    │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • Port 80, Protocol HTTP    │    │ • Port 443, Protocol HTTPS  │    │ • SNI additional certs       │          ║
║    │ • Redirect to HTTPS (if     │    │ • SSL policy, certificate   │    │ • Multi-domain support       │          ║
║    │   both listeners enabled)   │    │ • Fixed response default    │    │                              │          ║
║    │ • Fixed response (otherwise)│    │   action                    │    │                              │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                                                                                        ║
║    ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                    ACCESS LOGS S3 RESOURCES                                                  │    ║
║    │                           (all conditional: count = create_access_logs_bucket ? 1 : 0)                       │    ║
║    ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  ┌──────────────────────────┐  ┌───────────────────────────┐  ┌────────────────────────────────────────────┐ │    ║
║    │  │ aws_s3_bucket.access_logs│  │aws_s3_bucket_public_access│  │aws_s3_bucket_server_side_encryption       │ │    ║
║    │  │                          │  │    _block.access_logs     │  │          _configuration.access_logs       │ │    ║
║    │  │ • Auto-generated name    │  │                           │  │                                            │ │    ║
║    │  │ • force_destroy = true   │  │ • block_public_acls       │  │ • AES256 or KMS encryption                │ │    ║
║    │  │                          │  │ • block_public_policy     │  │                                            │ │    ║
║    │  └──────────────────────────┘  │ • ignore_public_acls      │  └────────────────────────────────────────────┘ │    ║
║    │                                │ • restrict_public_buckets │                                                 │    ║
║    │                                └───────────────────────────┘                                                 │    ║
║    │                                                                                                              │    ║
║    │  ┌──────────────────────────────────────┐  ┌────────────────────────────────────────────────────────────────┐│    ║
║    │  │ aws_s3_bucket_versioning.access_logs │  │            aws_s3_bucket_lifecycle_configuration               ││    ║
║    │  │                                      │  │                        .access_logs                            ││    ║
║    │  │ • Optional versioning                │  │                                                                ││    ║
║    │  └──────────────────────────────────────┘  │ • Expiration based on access_logs_retention_days               ││    ║
║    │                                            └────────────────────────────────────────────────────────────────┘│    ║
║    │                                                                                                              │    ║
║    │  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐│    ║
║    │  │                              aws_s3_bucket_policy.access_logs                                            ││    ║
║    │  │  • AllowELBRootAccount - ELB service account s3:PutObject                                                ││    ║
║    │  │  • AllowELBLogDelivery - delivery.logs.amazonaws.com s3:PutObject                                        ││    ║
║    │  │  • AllowELBLogDeliveryAclCheck - delivery.logs.amazonaws.com s3:GetBucketAcl                             ││    ║
║    │  │  • DenyInsecureTransport - Deny s3:* when SecureTransport = false                                        ││    ║
║    │  └──────────────────────────────────────────────────────────────────────────────────────────────────────────┘│    ║
║    └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
║    ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                               aws_wafv2_web_acl_association.this[0]                                          │    ║
║    │                              (count: waf_association_enabled ? 1 : 0)                                         │    ║
║    ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │ • Associates WAFv2 Web ACL with ALB                                                                          │    ║
║    │ • lifecycle precondition: web_acl_arn must be provided when enabled                                          │    ║
║    └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │    APPLICATION LOAD BALANCER            │   │              LISTENERS                  │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • alb_id                                │   │ • http_listener_arn                     │                            ║
║  │ • alb_arn                               │   │ • https_listener_arn                    │                            ║
║  │ • alb_arn_suffix                        │   └─────────────────────────────────────────┘                            ║
║  │ • alb_dns_name                          │                                                                          ║
║  │ • alb_zone_id                           │   ┌─────────────────────────────────────────┐                            ║
║  └─────────────────────────────────────────┘   │           SECURITY GROUP                │                            ║
║                                                ├─────────────────────────────────────────┤                            ║
║  ┌─────────────────────────────────────────┐   │ • security_group_id                     │                            ║
║  │           ACCESS LOGS                   │   │ • security_group_arn                    │                            ║
║  ├─────────────────────────────────────────┤   └─────────────────────────────────────────┘                            ║
║  │ • access_logs_bucket_name               │                                                                          ║
║  │ • access_logs_bucket_arn                │                                                                          ║
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
║                                        │   var.vpc_id            │                                                     ║
║                                        │   var.subnet_ids        │                                                     ║
║                                        │   var.ingress_*         │                                                     ║
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║  var.name ─────────────────────────────► module.security_group                                                        ║
║  var.tags ─────────────────────────────►         │                                                                    ║
║                                                  │                                                                    ║
║                                                  ▼                                                                    ║
║                              ┌───────────────────────────────────────────────────────────┐                             ║
║  var.internal_load_balancer_enabled ──────────────►│                                                           │                             ║
║  var.subnet_ids ────────────►│                                                           │                             ║
║  var.idle_timeout ──────────►│                                                           │                             ║
║  var.http2_enabled ──────────►│                                                           │                             ║
║  var.drop_invalid_* ────────►│                    aws_lb.this                            │                             ║
║  var.desync_* ──────────────►│                                                           │                             ║
║  var.preserve_host_* ───────►│                                                           │                             ║
║  var.xff_header_* ──────────►│                                                           │                             ║
║  var.waf_fail_open_enabled ──►│                                                           │                             ║
║  var.access_logs_enabled ────►│                                                           │                             ║
║  local.tags ────────────────►│                                                           │                             ║
║                              └────────────────────────────┬──────────────────────────────┘                             ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────┐                            ║
║           │                                               │                               │                            ║
║           ▼                                               ▼                               ▼                            ║
║  var.http_listener_enabled                    var.https_listener_enabled       var.access_logs_enabled                   ║
║  var.http_listener_port                      var.https_listener_port         var.access_logs_bucket_arn               ║
║  var.http_to_https_redirect_enabled                  var.certificate_arns            var.access_logs_retention_days           ║
║  var.default_action_*                        var.ssl_policy                  var.access_logs_kms_key_id               ║
║           │                                               │                               │                            ║
║           │                                               │                               │                            ║
║           ▼                                               ▼                               ▼                            ║
║  aws_lb_listener.http[0]                    aws_lb_listener.https[0]         aws_s3_bucket.access_logs[0]            ║
║                                             aws_lb_listener_certificate      aws_s3_bucket_policy                     ║
║                                             .additional                      aws_s3_bucket_*_configuration            ║
║                                                                                          │                            ║
║           │                                               │                               │                            ║
║           └───────────────────────────────────────────────┼───────────────────────────────┘                            ║
║                                                           │                                                            ║
║                                                           │                                                            ║
║  var.waf_association_enabled ─────────────────────────────►│                                                            ║
║  var.web_acl_arn ────────────────────────────────────────►│                                                            ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║                                        aws_wafv2_web_acl_association.this[0]                                          ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║                                                    MODULE OUTPUTS                                                      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_lb` | 1 | Application Load Balancer |
| `aws_lb_listener` (HTTP) | 0 or 1 | HTTP listener on port 80 |
| `aws_lb_listener` (HTTPS) | 0 or 1 | HTTPS listener on port 443 |
| `aws_lb_listener_certificate` | for_each | Additional SNI certificates |
| `module.security_group` | 1 | Security group for ALB |
| `aws_s3_bucket` | 0 or 1 | Access logs bucket (if created) |
| `aws_s3_bucket_public_access_block` | 0 or 1 | Block public access to logs bucket |
| `aws_s3_bucket_server_side_encryption_configuration` | 0 or 1 | Encryption for logs bucket |
| `aws_s3_bucket_versioning` | 0 or 1 | Versioning for logs bucket |
| `aws_s3_bucket_lifecycle_configuration` | 0 or 1 | Retention policy for logs |
| `aws_s3_bucket_policy` | 0 or 1 | Bucket policy for ELB log delivery |
| `aws_wafv2_web_acl_association` | 0 or 1 | WAF Web ACL association |

## FAQ

### When should I use HTTP vs HTTPS listeners?

| Scenario | Recommendation |
|----------|----------------|
| Production workloads | **HTTPS only** - Enable `https_listener_enabled = true`, disable HTTP or use redirect |
| Development/testing | HTTP may be acceptable, but HTTPS is still recommended |
| Internal services | HTTPS recommended even for internal traffic for defense in depth |
| HTTP to HTTPS migration | Enable both listeners with `http_to_https_redirect_enabled = true` |

**HTTP to HTTPS redirect behavior:**
- When both listeners are enabled and `http_to_https_redirect_enabled = true`, HTTP requests are automatically redirected to HTTPS with a 301 status code
- When only HTTP is enabled, requests get the default fixed response

```hcl
# Recommended production configuration
http_listener_enabled  = true   # Keep for redirect
https_listener_enabled = true
http_to_https_redirect_enabled = true  # Redirect HTTP to HTTPS
certificate_arns      = [aws_acm_certificate.main.arn]
```

### How do I integrate WAF with the ALB?

WAF integration requires two steps:

1. **Create a WAFv2 Web ACL** (outside this module):
```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = "my-web-acl"
  scope = "REGIONAL"  # Must be REGIONAL for ALB

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "myWebAcl"
  }
}
```

2. **Associate with the ALB**:
```hcl
module "alb" {
  source = "..."

  waf_association_enabled = true
  web_acl_arn            = aws_wafv2_web_acl.main.arn

  # Optional: Allow traffic when WAF is unavailable
  waf_fail_open_enabled = false  # Set to true for high availability
}
```

### How do access logs work?

Access logs provide detailed information about requests sent to your ALB. There are two options:

**Option 1: Let the module create the S3 bucket (recommended)**
```hcl
module "alb" {
  source = "..."

  access_logs_enabled         = true
  access_logs_retention_days = 90
  access_logs_kms_key_id     = aws_kms_key.logs.arn  # Optional
}
```

**Option 2: Use an existing S3 bucket**
```hcl
module "alb" {
  source = "..."

  access_logs_enabled     = true
  access_logs_bucket_arn = aws_s3_bucket.existing.arn
  access_logs_prefix     = "alb-logs"
}
```

**Important notes:**
- The bucket must have the correct policy to allow ELB log delivery
- Logs are delivered every 5 minutes
- Log files are in gzip format

### How do I add multiple SSL certificates for different domains?

Use SNI (Server Name Indication) with additional certificates:

```hcl
module "alb" {
  source = "..."

  https_listener_enabled = true

  # First ARN is the default cert; the rest are attached for SNI
  certificate_arns = [
    aws_acm_certificate.primary.arn,
    aws_acm_certificate.domain2.arn,
    aws_acm_certificate.domain3.arn,
  ]
}
```

The ALB will select the appropriate certificate based on the SNI hostname in the TLS handshake.

### What SSL policy should I use?

The default `ELBSecurityPolicy-TLS13-1-2-2021-06` is recommended for most use cases:

| Policy | TLS Versions | Use Case |
|--------|--------------|----------|
| `ELBSecurityPolicy-TLS13-1-2-2021-06` (default) | TLS 1.2, 1.3 | Recommended for most workloads |
| `ELBSecurityPolicy-TLS13-1-3-2021-06` | TLS 1.3 only | Maximum security, modern clients only |
| `ELBSecurityPolicy-TLS-1-2-2017-01` | TLS 1.2 | Legacy compatibility |

### Why does the module create a security group instead of accepting one?

The module creates its own security group to ensure:
- Ingress rules match the enabled listeners (HTTP and/or HTTPS)
- All egress is allowed for target health checks
- Consistent security configuration

To allow traffic from the ALB to your targets, reference the security group output:

```hcl
# Allow traffic from ALB to ECS tasks
resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = aws_security_group.ecs_tasks.id
}
```

## Security Considerations

- **TLS 1.3**: The default SSL policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`) enforces TLS 1.2 or 1.3.
- **Invalid Headers**: `invalid_header_drop_enabled` is enabled by default to prevent HTTP header injection attacks.
- **Desync Protection**: `desync_mitigation_mode` is set to `defensive` by default to protect against HTTP desync attacks.
- **WAF Integration**: Optionally attach a WAFv2 Web ACL for additional protection.
- **Access Logs Encryption**: When creating access logs bucket, encryption is enabled (AES256 by default, KMS optional).
- **Secure Transport**: Access logs bucket policy denies non-HTTPS requests.

## Notes

- At least 2 subnets in different availability zones are required for high availability.
- When HTTPS is enabled, a valid ACM certificate ARN must be provided.
- The security group allows all egress traffic to enable health checks and communication with targets.
- This module creates the ALB infrastructure only. Target groups and listener rules are created by service modules (e.g., ECS) that register targets with the ALB.
- The access logs S3 bucket is created with `force_destroy = true` for easier cleanup in development environments. For production, consider using an existing bucket.
- When using `waf_association_enabled`, you must also provide `web_acl_arn`.
- The module uses the `networking/security-groups` submodule for security group management.
