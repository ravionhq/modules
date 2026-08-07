# AWS Aurora

Creates an Amazon Aurora database cluster with support for Aurora MySQL and Aurora PostgreSQL engines. Includes provisioned instances, Serverless v2, global databases, custom endpoints, auto-scaling, subnet group, parameter groups, security group, Enhanced Monitoring, Performance Insights, Activity Streams, and optional CloudWatch alarms.

## Features

- **Multiple Engines**: Support for Aurora MySQL and Aurora PostgreSQL
- **High Availability**: Multi-AZ cluster with automatic failover and up to 15 read replicas
- **Serverless v2**: Auto-scaling capacity with Aurora Serverless v2 (0.5-256 ACUs)
- **Global Database**: Cross-region replication with Aurora Global Database
- **Auto-scaling**: Application Auto Scaling for read replicas based on CPU or connections
- **Security**: Encryption at rest, Secrets Manager integration for credentials, IAM database authentication
- **Monitoring**: Enhanced Monitoring, Performance Insights, and optional CloudWatch alarms
- **Activity Streams**: Database Activity Streams for compliance and auditing
- **Custom Endpoints**: Create READER or ANY type custom endpoints for workload isolation
- **Backtrack**: Backtrack support for Aurora MySQL (up to 72 hours)
- **Point-in-Time Recovery**: Automated backups with configurable retention
- **Flexible Instances**: Per-instance control or simplified reader count configuration
- **I/O-Optimized Storage**: Support for standard (`aurora`) and I/O-Optimized (`aurora-iopt1`) storage
- **IAM Role Associations**: S3 import/export, Lambda invoke, and other feature integrations
- **Flexible Security Groups**: Create new or use existing security groups

**Note**: Standard RDS instances (non-Aurora) are handled by the separate `database/rds` module.

## Usage

### Basic Aurora PostgreSQL Cluster

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  engine_version = "16.1"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  tags = {
    Environment = "development"
  }
}
```

### Production Aurora MySQL with Multiple Readers

```hcl
module "aurora_mysql" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-mysql"
  engine         = "aurora-mysql"
  engine_version = "8.0"
  instance_class = "db.r6g.xlarge"
  reader_count   = 2

  storage_type = "aurora-iopt1"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "admin"
  database_name   = "myapp"

  backup_retention_period      = 14
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Aurora MySQL features
  backtrack_window = 86400 # 24 hours

  allowed_security_group_ids = [module.app.security_group_id]

  tags = {
    Environment = "production"
  }
}
```

### Aurora Serverless v2

```hcl
module "aurora_serverless" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-serverless"
  engine         = "aurora-postgresql"
  engine_version = "16.1"
  instance_class = "db.serverless"

  serverless_v2_scaling = {
    min_capacity = 0.5
    max_capacity = 16
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### With Auto-scaling

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  instance_class = "db.r6g.large"
  reader_count   = 1

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Auto-scaling for read replicas
  autoscaling_enabled       = true
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 5
  autoscaling_target_cpu   = 70
}
```

### With Custom Endpoints

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  instance_class = "db.r6g.large"
  reader_count   = 3

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  custom_endpoints = {
    analytics = {
      type           = "READER"
      static_members = ["my-postgres-reader-1"]
    }
    reporting = {
      type             = "READER"
      excluded_members = ["my-postgres-writer"]
    }
  }
}
```

### With CloudWatch Alarms

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # CloudWatch Alarms
  cloudwatch_alarms_creation_enabled               = true
  cloudwatch_alarm_cpu_threshold         = 75
  cloudwatch_alarm_memory_threshold      = 536870912 # 512 MiB
  cloudwatch_alarm_connections_threshold = 200
  cloudwatch_alarm_actions               = [aws_sns_topic.alerts.arn]
  cloudwatch_ok_actions                  = [aws_sns_topic.alerts.arn]
}
```

### With Enhanced Monitoring and CloudWatch Logs

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-mysql"
  engine         = "aurora-mysql"
  engine_version = "8.0"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "admin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Enhanced Monitoring
  monitoring_interval    = 30
  monitoring_role_creation_enabled = true

  # Performance Insights (enabled by default)
  performance_insights_retention_period = 7

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["error", "slowquery", "audit"]
}
```

### Global Database

```hcl
# Primary region
module "aurora_primary" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-global-db"
  engine         = "aurora-postgresql"
  engine_version = "16.1"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Create global cluster
  global_cluster_creation_enabled    = true
  global_cluster_identifier = "my-global-db"
}

# Secondary region (in a separate Terraform workspace/state)
module "aurora_secondary" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-global-db-secondary"
  engine         = "aurora-postgresql"
  engine_version = "16.1"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Join existing global cluster
  global_cluster_identifier = "my-global-db"
  source_region             = "us-east-1"
}
```

### Heterogeneous Instance Configuration

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  instance_class = "db.r6g.xlarge"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Per-instance control (overrides reader_count)
  instances = {
    writer = {
      instance_class = "db.r6g.xlarge"
      promotion_tier = 0
    }
    reader-1 = {
      instance_class = "db.r6g.large"
      promotion_tier = 1
    }
    analytics = {
      instance_class = "db.r6g.2xlarge"
      promotion_tier = 15
    }
  }
}
```

### Using Existing Security Group

```hcl
module "aurora" {
  source = "git::https://github.com/user/ravion-modules.git//database/aurora?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "aurora-postgresql"
  instance_class = "db.r6g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  master_username = "dbadmin"

  # Use existing security group instead of creating one
  security_group_creation_enabled = false
  security_group_id     = aws_security_group.existing.id
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Aurora cluster. Used as a prefix for all resources. | `string` | n/a | yes |
| engine | The Aurora database engine type. Valid values: aurora-mysql, aurora-postgresql. | `string` | n/a | yes |
| instance_class | The instance class for Aurora instances. Must start with `db.`. | `string` | n/a | yes |
| vpc_id | The VPC ID where the Aurora cluster will be created. | `string` | n/a | yes |
| subnet_ids | A list of VPC subnet IDs for the DB subnet group (minimum 2). | `list(string)` | n/a | yes |
| master_username | Username for the master DB user. | `string` | n/a | yes |
| tags | A map of tags to add to all resources. | `map(string)` | `{}` | no |
| engine_version | The Aurora engine version. | `string` | `null` | no |
| database_name | Name for an automatically created database on cluster creation. | `string` | `null` | no |
| port | The port on which the DB accepts connections (defaults: 3306 MySQL, 5432 PostgreSQL). | `number` | `null` | no |
| storage_type | Storage type: aurora (standard) or aurora-iopt1 (I/O-Optimized). | `string` | `"aurora"` | no |
| network_type | The network type of the cluster: IPV4 or DUAL. | `string` | `"IPV4"` | no |
| http_endpoint_enabled | Enable HTTP endpoint (Data API) for the Aurora cluster. | `bool` | `false` | no |
| local_write_forwarding_enabled | Enable local write forwarding (Aurora MySQL only). | `bool` | `false` | no |
| ca_certificate_identifier | The identifier of the CA certificate for the DB instances. | `string` | `null` | no |
| immediate_apply_enabled | Apply cluster modifications immediately. | `bool` | `false` | no |
| deletion_protection_enabled | Enable deletion protection. | `bool` | `true` | no |
| availability_zones | List of EC2 Availability Zones for the DB cluster. | `list(string)` | `[]` | no |
| public_access_enabled | Whether instances are publicly accessible. | `bool` | `false` | no |
| db_subnet_group_name | Existing DB subnet group name. | `string` | `null` | no |
| security_group_creation_enabled | Whether to create a new security group. | `bool` | `true` | no |
| security_group_id | Existing security group ID to use. | `string` | `null` | no |
| security_group_ids | Additional security group IDs to attach. | `list(string)` | `[]` | no |
| allowed_security_group_ids | Security group IDs allowed to access the cluster. | `list(string)` | `[]` | no |
| allowed_cidr_blocks | CIDR blocks allowed to access the cluster. | `list(string)` | `[]` | no |
| master_password | Optional master password when Secrets Manager management is disabled. Leave null to preserve an imported or restored cluster's externally managed password. | `string` | `null` | no |
| master_user_password_management_enabled | Use Secrets Manager for the master password. Disable before importing a cluster whose existing password is managed externally. | `bool` | `true` | no |
| master_user_password_preservation_enabled | Preserve an existing externally managed password by omitting password configuration. The named cluster must already exist in AWS, and password management must be disabled. | `bool` | `false` | no |
| master_user_secret_kms_key_id | KMS key ARN for the Secrets Manager secret. | `string` | `null` | no |
| iam_database_authentication_enabled | Enable IAM database authentication. | `bool` | `false` | no |
| storage_encryption_enabled | Enable encryption at rest. | `bool` | `true` | no |
| kms_key_id | KMS key ARN for storage encryption. | `string` | `null` | no |
| reader_count | Number of reader instances (0-15). | `number` | `1` | no |
| reader_instance_class | Instance class for readers (defaults to instance_class). | `string` | `null` | no |
| instances | Map of per-instance configurations (overrides reader_count). | `map(object)` | `{}` | no |
| serverless_v2_scaling | Serverless v2 scaling configuration (min_capacity, max_capacity). | `object` | `null` | no |
| promotion_tier | Default failover priority for instances (0-15). | `number` | `null` | no |
| backup_retention_period | Days to retain automated backups (1-35). | `number` | `7` | no |
| preferred_backup_window | Daily backup window (HH:MM-HH:MM in UTC). | `string` | `null` | no |
| snapshot_tag_copying_enabled | Copy tags to snapshots. | `bool` | `true` | no |
| final_snapshot_creation_enabled | Create a final snapshot on deletion. | `bool` | `true` | no |
| final_snapshot_identifier | Name for the final snapshot. | `string` | `null` | no |
| snapshot_identifier | Snapshot ID to restore from. | `string` | `null` | no |
| restore_to_point_in_time | Point-in-time recovery configuration. | `object` | `null` | no |
| backtrack_window | Backtrack window in seconds (0-259200, Aurora MySQL only). | `number` | `0` | no |
| preferred_maintenance_window | Weekly maintenance window (ddd:HH:MM-ddd:HH:MM). | `string` | `null` | no |
| major_version_upgrade_enabled | Allow major engine version upgrades. | `bool` | `false` | no |
| minor_version_auto_upgrade_enabled | Enable automatic minor version upgrades. | `bool` | `true` | no |
| cluster_parameter_group_creation_enabled | Whether to create a cluster parameter group. | `bool` | `true` | no |
| cluster_parameter_group_name | Existing cluster parameter group name. | `string` | `null` | no |
| cluster_parameter_group_family | Cluster parameter group family (auto-derived if not set). | `string` | `null` | no |
| cluster_parameters | Cluster parameter name/value pairs. | `list(object)` | `[]` | no |
| db_parameter_group_creation_enabled | Whether to create a DB parameter group. | `bool` | `true` | no |
| db_parameter_group_name | Existing DB parameter group name. | `string` | `null` | no |
| db_parameter_group_family | DB parameter group family (auto-derived if not set). | `string` | `null` | no |
| db_parameters | DB parameter name/value pairs. | `list(object)` | `[]` | no |
| enabled_cloudwatch_logs_exports | Log types to export to CloudWatch. | `list(string)` | `[]` | no |
| monitoring_interval | Enhanced Monitoring interval (0, 1, 5, 10, 15, 30, 60). | `number` | `0` | no |
| monitoring_role_arn | IAM role ARN for Enhanced Monitoring. | `string` | `null` | no |
| monitoring_role_creation_enabled | Create IAM role for Enhanced Monitoring. | `bool` | `true` | no |
| performance_insights_enabled | Enable Performance Insights. | `bool` | `true` | no |
| performance_insights_retention_period | Performance Insights retention (7 or 31-731 days). | `number` | `7` | no |
| performance_insights_kms_key_id | KMS key ARN for Performance Insights. | `string` | `null` | no |
| cloudwatch_alarms_creation_enabled | Create CloudWatch alarms. | `bool` | `false` | no |
| cloudwatch_alarm_cpu_threshold | CPU utilization threshold (%). | `number` | `80` | no |
| cloudwatch_alarm_memory_threshold | Freeable memory threshold (bytes). | `number` | `268435456` | no |
| cloudwatch_alarm_connections_threshold | Database connections threshold. | `number` | `100` | no |
| cloudwatch_alarm_actions | ARNs to notify on ALARM state. | `list(string)` | `[]` | no |
| cloudwatch_ok_actions | ARNs to notify on OK state. | `list(string)` | `[]` | no |
| cloudwatch_alarm_evaluation_periods | Number of evaluation periods. | `number` | `2` | no |
| cloudwatch_alarm_period | Alarm period in seconds. | `number` | `300` | no |
| autoscaling_enabled | Enable auto-scaling for read replicas. | `bool` | `false` | no |
| autoscaling_min_capacity | Minimum read replicas when auto-scaling. | `number` | `1` | no |
| autoscaling_max_capacity | Maximum read replicas when auto-scaling. | `number` | `3` | no |
| autoscaling_target_cpu | Target CPU utilization (%) for auto-scaling. | `number` | `70` | no |
| autoscaling_target_connections | Target connections for auto-scaling. | `number` | `null` | no |
| autoscaling_scale_in_cooldown | Scale-in cooldown period (seconds). | `number` | `300` | no |
| autoscaling_scale_out_cooldown | Scale-out cooldown period (seconds). | `number` | `300` | no |
| autoscaling_policy_name | Auto-scaling policy name (auto-generated if null). | `string` | `null` | no |
| custom_endpoints | Map of custom endpoint configurations. | `map(object)` | `{}` | no |
| global_cluster_creation_enabled | Whether to create a global Aurora cluster. | `bool` | `false` | no |
| global_cluster_identifier | The global cluster identifier. | `string` | `null` | no |
| source_region | Source region for cross-region replication. | `string` | `null` | no |
| global_write_forwarding_enabled | Enable global write forwarding (Aurora PostgreSQL only). | `bool` | `false` | no |
| activity_stream_enabled | Enable Database Activity Streams. | `bool` | `false` | no |
| activity_stream_mode | Activity stream mode: sync or async. | `string` | `"async"` | no |
| activity_stream_kms_key_id | KMS key ARN for activity stream (required when enabled). | `string` | `null` | no |
| iam_role_associations | Map of IAM role associations (S3_IMPORT, S3_EXPORT, LAMBDA_INVOKE, etc.). | `map(object)` | `{}` | no |
| proxy_creation_enabled | Whether to create an RDS Proxy in front of the cluster. | `bool` | `false` | no |
| proxy_auth_secret_arns | Secrets Manager secret ARNs for proxy auth (defaults to the managed master user secret). | `list(string)` | `[]` | no |
| proxy_secret_kms_key_arns | KMS key ARNs used to encrypt the proxy auth secrets (customer-managed keys). | `list(string)` | `[]` | no |
| proxy_iam_auth_enabled | Require IAM authentication for proxy connections. | `bool` | `false` | no |
| proxy_tls_requirement_enabled | Require TLS for proxy connections. | `bool` | `true` | no |
| proxy_debug_logging_enabled | Log detailed proxy connection information to CloudWatch Logs. | `bool` | `false` | no |
| proxy_idle_client_timeout | Seconds a client connection can be idle before the proxy disconnects it. | `number` | `1800` | no |
| proxy_connection_borrow_timeout | Seconds the proxy waits for an available connection in the pool. | `number` | `120` | no |
| proxy_init_query | SQL statements the proxy runs when opening each new database connection. | `string` | `null` | no |
| proxy_max_connections_percent | Max proxy connection pool size (% of database max_connections). | `number` | `100` | no |
| proxy_max_idle_connections_percent | Max idle proxy connections (% of database max_connections). | `number` | `50` | no |
| proxy_session_pinning_filters | Session pinning filters (EXCLUDE_VARIABLE_SETS). | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | The ID of the Aurora cluster. |
| cluster_arn | The ARN of the Aurora cluster. |
| cluster_identifier | The cluster identifier. |
| cluster_resource_id | The resource ID of the Aurora cluster. |
| cluster_engine_version_actual | The actual engine version running. |
| cluster_endpoint | The writer endpoint for the Aurora cluster. |
| cluster_reader_endpoint | The reader endpoint (load-balanced across readers). |
| cluster_port | The port on which the cluster accepts connections. |
| cluster_hosted_zone_id | The Route53 hosted zone ID. |
| cluster_database_name | The database name. |
| cluster_master_username | The master username. |
| cluster_master_user_secret_arn | The Secrets Manager secret ARN for credentials. |
| instance_identifiers | Map of instance key to instance identifier. |
| instance_arns | Map of instance key to instance ARN. |
| instance_endpoints | Map of instance key to instance endpoint. |
| custom_endpoint_arns | Map of custom endpoint key to endpoint ARN. |
| security_group_id | The security group ID. |
| security_group_arn | The security group ARN. |
| db_subnet_group_name | The DB subnet group name. |
| db_subnet_group_arn | The DB subnet group ARN. |
| cluster_parameter_group_name | The cluster parameter group name. |
| cluster_parameter_group_arn | The cluster parameter group ARN. |
| db_parameter_group_name | The DB parameter group name. |
| db_parameter_group_arn | The DB parameter group ARN. |
| enhanced_monitoring_iam_role_arn | The Enhanced Monitoring IAM role ARN. |
| cloudwatch_alarm_arns | Map of CloudWatch alarm ARNs. |
| global_cluster_id | The global cluster ID. |
| global_cluster_arn | The global cluster ARN. |
| activity_stream_kinesis_stream_name | The Kinesis data stream name for activity stream. |
| activity_stream_kms_key_id | The KMS key ID for activity stream. |
| autoscaling_target_arn | The Application Auto Scaling target ARN. |
| proxy_endpoint | The RDS Proxy endpoint (null when no proxy is created). |
| proxy_arn | The RDS Proxy ARN (null when no proxy is created). |
| proxy_security_group_id | The RDS Proxy security group ID (null when no proxy is created). |

## Security Considerations

- **Encryption at Rest**: Enabled by default using AWS managed keys. Optionally provide your own KMS key.
- **Secrets Manager**: Master password managed by Secrets Manager by default. No plaintext passwords in state.
- **IAM Authentication**: Optionally enable IAM database authentication for MySQL and PostgreSQL.
- **VPC Only**: The cluster is deployed within your VPC with no public access by default.
- **Security Groups**: Fine-grained access control via security group rules.
- **Deletion Protection**: Enabled by default to prevent accidental deletion.
- **Activity Streams**: Optional audit trail of database activity for compliance.

## CloudWatch Logs by Engine

Valid log export types depend on the database engine:

| Engine | Valid Log Types |
|--------|----------------|
| Aurora MySQL | `audit`, `error`, `general`, `slowquery` |
| Aurora PostgreSQL | `postgresql` |

## Engine-Specific Features

| Feature | Aurora MySQL | Aurora PostgreSQL |
|---------|:-----------:|:-----------------:|
| Backtrack (up to 72 hours) | Yes | No |
| Local Write Forwarding | Yes | No |
| Global Write Forwarding | No | Yes |
| Serverless v2 | Yes | Yes |
| Global Database | Yes | Yes |
| Activity Streams | Yes | Yes |
| Performance Insights | Yes | Yes |
| Data API (HTTP endpoint) | Yes | Yes |

## Notes

- **RDS Instances**: Use the separate `database/rds` module for standard (non-Aurora) RDS instances.
- **Aurora vs RDS**: Aurora uses a cluster-based architecture (`aws_rds_cluster` + `aws_rds_cluster_instance`) rather than standalone instances (`aws_db_instance`).
- **Read Replicas**: Aurora supports up to 15 read replicas with automatic failover. Use `reader_count` for homogeneous replicas or `instances` map for heterogeneous configurations.
- **Serverless v2**: When using `serverless_v2_scaling`, set `instance_class = "db.serverless"`. Capacity scales between `min_capacity` and `max_capacity` ACUs.
- **Global Database**: A global database spans multiple regions. Use `global_cluster_creation_enabled = true` for the primary cluster and `global_cluster_identifier` to join from secondary regions.
- **Parameter Group Family**: Auto-detected from engine and version if not specified.
- **Backtrack**: Only supported on Aurora MySQL. Set `backtrack_window` in seconds (max 259200 = 72 hours).
- **Activity Streams**: Requires a KMS key. Use `async` mode for minimal performance impact.
- **RDS Proxy**: Use a separate module for RDS Proxy, which works with both Aurora and RDS.

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            AWS Aurora Cluster                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                           Aurora Core                                   │  │
│  │  • Aurora MySQL or Aurora PostgreSQL                                    │  │
│  │  • Cluster endpoint (writer) + Reader endpoint (load-balanced)         │  │
│  │  • Encryption at rest (KMS)                                            │  │
│  │  • Serverless v2 or provisioned instances                              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   DB Subnet Group    │  │  Cluster Param Group │  │   DB Param Group   │  │
│  │  • Private subnets   │  │  • Cluster settings  │  │  • Instance params │  │
│  │  • Multi-AZ support  │  │  • Custom params     │  │  • Custom params   │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Security Group     │  │  Cluster Instances   │  │   Secrets Manager  │  │
│  │  • Ingress rules     │  │  • Writer + Readers  │  │  • Master password │  │
│  │  • CIDR/SG sources   │  │  • Auto failover     │  │  • Auto rotation   │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Enhanced Monitor   │  │  Custom Endpoints    │  │   Activity Stream  │  │
│  │  • OS-level metrics  │  │  • READER endpoints  │  │  • Kinesis stream  │  │
│  │  • IAM role          │  │  • ANY endpoints     │  │  • Audit logging   │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────────────────────────────┐  │
│  │   Auto-scaling       │  │              CloudWatch Alarms               │  │
│  │  • CPU-based policy  │  │  • CPU utilization    • Freeable memory      │  │
│  │  • Connection-based  │  │  • Database connections                      │  │
│  └──────────────────────┘  └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_rds_global_cluster` | 0 or 1 | Global cluster (if `global_cluster_creation_enabled = true`) |
| `aws_rds_cluster` | 1 | Aurora cluster (core resource) |
| `aws_rds_cluster_instance` | 1 to N | Writer + reader instances (via `for_each`) |
| `aws_rds_cluster_endpoint` | 0 to N | Custom endpoints (via `for_each`) |
| `aws_db_subnet_group` | 0 or 1 | Subnet group (if not using existing) |
| `aws_rds_cluster_parameter_group` | 0 or 1 | Cluster parameter group (if `cluster_parameter_group_creation_enabled = true`) |
| `aws_db_parameter_group` | 0 or 1 | Instance parameter group (if `db_parameter_group_creation_enabled = true`) |
| `module.security_group` | 0 or 1 | Security group via `networking/security-groups` (if `security_group_creation_enabled = true`) |
| `aws_iam_role` | 0 or 1 | Enhanced Monitoring IAM role (if `monitoring_role_creation_enabled = true` and `monitoring_interval > 0`) |
| `aws_iam_role_policy_attachment` | 0 or 1 | Monitoring role policy attachment |
| `aws_cloudwatch_metric_alarm` | 0 or 3 | CPU, memory, connections alarms (if `cloudwatch_alarms_creation_enabled = true`) |
| `aws_rds_cluster_activity_stream` | 0 or 1 | Activity stream (if `activity_stream_enabled = true`) |
| `aws_rds_cluster_role_association` | 0 to N | IAM role associations (via `for_each`) |
| `aws_appautoscaling_target` | 0 or 1 | Auto-scaling target (if `autoscaling_enabled = true`) |
| `aws_appautoscaling_policy` | 0 to 2 | CPU and/or connection scaling policies |
