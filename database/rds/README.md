# AWS RDS

Creates an Amazon RDS database instance with support for MySQL, PostgreSQL, MariaDB, Oracle, and SQL Server engines. Includes subnet group, parameter group, option group, security group, Enhanced Monitoring, Performance Insights, and optional CloudWatch alarms.

## Features

- **Multiple Engines**: Support for MySQL, PostgreSQL, MariaDB, Oracle (EE, SE2), and SQL Server (EE, SE, Express, Web)
- **High Availability**: Multi-AZ deployment and read replicas for horizontal scaling
- **Security**: Encryption at rest, Secrets Manager integration for credentials, IAM database authentication
- **Monitoring**: Enhanced Monitoring, Performance Insights, and optional CloudWatch alarms
- **Flexible Storage**: Support for gp2, gp3, io1, io2 storage types with auto-scaling
- **Point-in-Time Recovery**: Automated backups with configurable retention
- **Blue/Green Deployments**: Zero-downtime updates with rollback capability
- **Flexible Security Groups**: Create new or use existing security groups

**Note**: Aurora is a separate module (`database/aurora`) due to its fundamentally different resource model (`aws_rds_cluster` vs `aws_db_instance`).

## Usage

### Basic PostgreSQL Instance

```hcl
module "postgres" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-postgres"
  engine               = "postgres"
  engine_major_version = "15"
  engine_minor_version = "4"
  instance_class       = "db.t4g.micro"

  allocated_storage = 20

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  tags = {
    Environment = "development"
  }
}
```

### Production MySQL with Multi-AZ

```hcl
module "mysql" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-mysql"
  engine               = "mysql"
  engine_major_version = "8.0"
  instance_class       = "db.r6g.large"

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125

  multi_az_enabled = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "admin"
  db_name  = "myapp"

  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  allowed_security_group_ids = [module.app.security_group_id]

  tags = {
    Environment = "production"
  }
}
```

### With Read Replicas

```hcl
module "postgres_with_replicas" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-postgres"
  engine               = "postgres"
  engine_major_version = "15"
  engine_minor_version = "4"
  instance_class       = "db.r6g.large"

  allocated_storage = 100

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"

  # Read replicas
  read_replica_creation_enabled  = true
  read_replica_count   = 2

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### With CloudWatch Alarms

```hcl
module "postgres" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "postgres"
  instance_class = "db.t4g.small"

  allocated_storage = 50

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # CloudWatch Alarms
  cloudwatch_alarms_creation_enabled               = true
  cloudwatch_alarm_cpu_threshold         = 75
  cloudwatch_alarm_storage_threshold     = 10737418240 # 10 GiB
  cloudwatch_alarm_connections_threshold = 100
  cloudwatch_alarm_actions               = [aws_sns_topic.alerts.arn]
  cloudwatch_ok_actions                  = [aws_sns_topic.alerts.arn]
}
```

### With Enhanced Monitoring and CloudWatch Logs

```hcl
module "mysql" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-mysql"
  engine               = "mysql"
  engine_major_version = "8.0"
  instance_class       = "db.t4g.medium"

  allocated_storage = 50

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "admin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Enhanced Monitoring
  monitoring_interval     = 30
  monitoring_role_creation_enabled  = true

  # Performance Insights (enabled by default)
  performance_insights_retention_period = 7

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["error", "slowquery", "general"]
}
```

### Using Existing Security Group

```hcl
module "postgres" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name           = "my-postgres"
  engine         = "postgres"
  instance_class = "db.t4g.micro"

  allocated_storage = 20

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"

  # Use existing security group instead of creating one
  security_group_creation_enabled = false
  security_group_id     = aws_security_group.existing.id
}
```

### With Custom Parameters

```hcl
module "postgres" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-postgres"
  engine               = "postgres"
  engine_major_version = "15"
  engine_minor_version = "4"
  instance_class       = "db.r6g.large"

  allocated_storage = 100

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "dbadmin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Custom parameters
  parameter_group_family = "postgres15"
  parameters = [
    {
      name         = "log_statement"
      value        = "all"
      apply_method = "immediate"
    },
    {
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    }
  ]
}
```

Managed parameter groups created by this module are named `rds-${name}` so the same name slug can be reused by other module types.

### Oracle with Option Group

```hcl
module "oracle" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-oracle"
  engine               = "oracle-ee"
  engine_major_version = "19"
  engine_minor_version = "0.0.0.0.ru-2023-10.rur-2023-10.r1"
  instance_class       = "db.r6i.large"
  license_model        = "bring-your-own-license"

  allocated_storage = 100

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username       = "admin"
  character_set_name = "AL32UTF8"

  allowed_security_group_ids = [module.app.security_group_id]

  # Option group
  option_group_creation_enabled = true
  options = [
    {
      option_name = "STATSPACK"
    },
    {
      option_name = "S3_INTEGRATION"
      version     = "1.0"
    }
  ]
}
```

### With Blue/Green Deployment

```hcl
module "mysql" {
  source = "git::https://github.com/user/ravion-modules.git//database/rds?ref=v1.0.0"

  name                 = "my-mysql"
  engine               = "mysql"
  engine_major_version = "8.0"
  instance_class       = "db.r6g.large"

  allocated_storage = 100

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  username = "admin"

  allowed_security_group_ids = [module.app.security_group_id]

  # Enable Blue/Green deployments
  blue_green_update = {
    enabled = true
  }
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
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| engine | The database engine to use. | `string` | n/a | yes |
| instance_class | The compute and memory capacity of the DB instance. | `string` | n/a | yes |
| allocated_storage | The allocated storage in GiB. AWS supports increasing allocated storage after creation, but not reducing it in place. | `number` | n/a | yes |
| vpc_id | The ID of the VPC where the RDS instance will be created. | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the DB subnet group. | `list(string)` | n/a | yes |
| username | The master username for the database. | `string` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| engine_major_version | The major version of the database engine. Examples: 15 for PostgreSQL or SQL Server, 8.0 for MySQL, 19 for Oracle. | `string` | `null` | no |
| engine_minor_version | The optional minor version of the database engine. | `string` | `null` | no |
| license_model | The license model for Oracle/SQL Server. | `string` | `null` | no |
| max_allocated_storage | Upper limit for storage autoscaling (0 to disable). AWS can grow storage up to this limit, but storage cannot be reduced in place. | `number` | `0` | no |
| storage_type | The storage type: gp2, gp3, io1, io2, or standard. | `string` | `"gp3"` | no |
| iops | Provisioned IOPS for io1/io2, optional for gp3. | `number` | `null` | no |
| storage_throughput | Storage throughput in MiB/s (gp3 only). | `number` | `null` | no |
| storage_encryption_enabled | Enable encryption at rest. | `bool` | `true` | no |
| kms_key_id | KMS key ARN for storage encryption. | `string` | `null` | no |
| port | Database port (defaults per engine). | `number` | `null` | no |
| public_access_enabled | Whether the instance is publicly accessible. | `bool` | `false` | no |
| availability_zone | AZ for the instance (ignored if multi_az_enabled). | `string` | `null` | no |
| ca_cert_identifier | CA certificate identifier. | `string` | `null` | no |
| security_group_creation_enabled | Whether to create a security group. | `bool` | `true` | no |
| security_group_id | Existing security group ID to use. | `string` | `null` | no |
| allowed_security_group_ids | Security group IDs allowed to access the instance. | `list(string)` | `[]` | no |
| allowed_cidr_blocks | CIDR blocks allowed to access the instance. | `list(string)` | `[]` | no |
| multi_az_enabled | Enable Multi-AZ deployment. | `bool` | `false` | no |
| read_replica_creation_enabled | Whether to create read replicas. | `bool` | `false` | no |
| read_replica_count | Number of read replicas to create. | `number` | `1` | no |
| read_replica_instance_class | Instance class for read replicas. | `string` | `null` | no |
| read_replica_availability_zones | AZs for read replicas. | `list(string)` | `[]` | no |
| password | Optional master password when Secrets Manager management is disabled. Leave null to preserve an imported or restored database's externally managed password. | `string` | `null` | no |
| master_user_password_management_enabled | Use Secrets Manager for the master password. Disable before importing a database whose existing password is managed externally. | `bool` | `true` | no |
| master_user_password_preservation_enabled | Preserve an existing externally managed password by omitting password configuration. The named database must already exist in AWS, and password management must be disabled. | `bool` | `false` | no |
| master_user_secret_kms_key_id | KMS key for Secrets Manager secret. | `string` | `null` | no |
| iam_database_authentication_enabled | Enable IAM database authentication. | `bool` | `false` | no |
| db_name | Database name to create. | `string` | `null` | no |
| character_set_name | Character set for Oracle/SQL Server. | `string` | `null` | no |
| timezone | Timezone for SQL Server. | `string` | `null` | no |
| domain | Active Directory directory ID. | `string` | `null` | no |
| domain_iam_role_name | IAM role for AD integration. | `string` | `null` | no |
| backup_retention_period | Days to retain automated backups. | `number` | `7` | no |
| backup_window | Daily backup window (HH:MM-HH:MM). | `string` | `null` | no |
| snapshot_tag_copying_enabled | Copy tags to snapshots. | `bool` | `true` | no |
| automated_backups_deletion_enabled | Delete backups on instance deletion. | `bool` | `true` | no |
| snapshot_identifier | Snapshot ID to restore from. | `string` | `null` | no |
| final_snapshot_identifier | Name for final snapshot on deletion. | `string` | `null` | no |
| final_snapshot_creation_enabled | Create a final snapshot on deletion. | `bool` | `true` | no |
| restore_to_point_in_time | Point-in-time recovery configuration. | `object` | `null` | no |
| maintenance_window | Weekly maintenance window. | `string` | `null` | no |
| minor_version_auto_upgrade_enabled | Enable automatic minor version upgrades. | `bool` | `true` | no |
| major_version_upgrade_enabled | Allow major version upgrades. | `bool` | `false` | no |
| immediate_apply_enabled | Apply changes immediately. | `bool` | `false` | no |
| deletion_protection_enabled | Enable deletion protection. | `bool` | `true` | no |
| enabled_cloudwatch_logs_exports | Log types to export to CloudWatch. | `list(string)` | `[]` | no |
| monitoring_interval | Enhanced Monitoring interval (0 to disable). | `number` | `0` | no |
| monitoring_role_arn | IAM role ARN for Enhanced Monitoring. | `string` | `null` | no |
| monitoring_role_creation_enabled | Create IAM role for Enhanced Monitoring. | `bool` | `true` | no |
| performance_insights_enabled | Enable Performance Insights. | `bool` | `true` | no |
| performance_insights_retention_period | Performance Insights retention (days). | `number` | `7` | no |
| performance_insights_kms_key_id | KMS key for Performance Insights. | `string` | `null` | no |
| cloudwatch_alarms_creation_enabled | Create CloudWatch alarms. | `bool` | `false` | no |
| cloudwatch_alarm_cpu_threshold | CPU utilization threshold (%). | `number` | `80` | no |
| cloudwatch_alarm_storage_threshold | Free storage threshold (bytes). | `number` | `5368709120` | no |
| cloudwatch_alarm_connections_threshold | Database connections threshold. | `number` | `100` | no |
| cloudwatch_alarm_actions | ARNs to notify on ALARM. | `list(string)` | `[]` | no |
| cloudwatch_ok_actions | ARNs to notify on OK. | `list(string)` | `[]` | no |
| parameter_group_creation_enabled | Whether to create a parameter group. Managed groups are named `rds-${name}`. | `bool` | `true` | no |
| parameter_group_name | Existing parameter group name to use when creation is disabled. | `string` | `null` | no |
| parameter_group_family | Parameter group family. | `string` | `null` | no |
| parameters | Parameter name/value pairs. | `list(object)` | `[]` | no |
| option_group_creation_enabled | Whether to create an option group. | `bool` | `false` | no |
| option_group_name | Existing option group name. | `string` | `null` | no |
| option_group_engine_version | Option group major engine version. | `string` | `null` | no |
| options | Options for the option group. | `list(object)` | `[]` | no |
| blue_green_update | Blue/Green deployment configuration. | `object` | `null` | no |
| proxy_creation_enabled | Whether to create an RDS Proxy in front of the database. | `bool` | `false` | no |
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
| db_instance_id | The ID of the RDS instance. |
| db_instance_arn | The ARN of the RDS instance. |
| db_instance_identifier | The identifier of the RDS instance. |
| db_instance_resource_id | The resource ID of the RDS instance. |
| db_instance_status | The status of the RDS instance. |
| db_instance_availability_zone | The availability zone of the RDS instance. |
| endpoint | The connection endpoint in address:port format. |
| address | The hostname of the RDS instance. |
| port | The port on which the database accepts connections. |
| hosted_zone_id | The Route53 hosted zone ID. |
| engine | The database engine used. |
| engine_version_actual | The actual engine version running. |
| db_name | The database name. |
| username | The master username. |
| master_user_secret_arn | The Secrets Manager secret ARN for credentials. |
| read_replica_identifiers | List of read replica identifiers. |
| read_replica_endpoints | List of read replica endpoints. |
| read_replica_arns | List of read replica ARNs. |
| security_group_id | The security group ID. |
| security_group_arn | The security group ARN. |
| db_subnet_group_name | The DB subnet group name. |
| db_subnet_group_arn | The DB subnet group ARN. |
| db_parameter_group_name | The DB parameter group name. Managed groups are named `rds-${name}`. |
| db_parameter_group_arn | The parameter group ARN. |
| db_option_group_name | The option group name. |
| db_option_group_arn | The option group ARN. |
| enhanced_monitoring_iam_role_arn | The Enhanced Monitoring IAM role ARN. |
| cloudwatch_alarm_arns | Map of CloudWatch alarm ARNs. |
| proxy_endpoint | The RDS Proxy endpoint (null when no proxy is created). |
| proxy_arn | The RDS Proxy ARN (null when no proxy is created). |
| proxy_security_group_id | The RDS Proxy security group ID (null when no proxy is created). |

## Security Considerations

- **Encryption at Rest**: Enabled by default using AWS managed keys. Optionally provide your own KMS key.
- **Secrets Manager**: Master password managed by Secrets Manager by default. No plaintext passwords in state.
- **IAM Authentication**: Optionally enable IAM database authentication for MySQL and PostgreSQL.
- **VPC Only**: The instance is deployed within your VPC with no public access by default.
- **Security Groups**: Fine-grained access control via security group rules.
- **Deletion Protection**: Enabled by default to prevent accidental deletion.

## CloudWatch Logs by Engine

Valid log export types depend on the database engine:

| Engine | Valid Log Types |
|--------|----------------|
| MySQL | `error`, `general`, `slowquery`, `audit` |
| PostgreSQL | `postgresql`, `upgrade` |
| MariaDB | `error`, `general`, `slowquery`, `audit` |
| Oracle | `alert`, `audit`, `listener`, `trace`, `oemagent` |
| SQL Server | `agent`, `error` |

## Notes

- **Aurora**: Use the separate `database/aurora` module for Aurora databases.
- **Multi-AZ**: Provides a synchronous standby replica in a different AZ for automatic failover.
- **Read Replicas**: Asynchronous replicas for read scaling. Not available for SQL Server.
- **Parameter Group Family**: Auto-detected from engine and version if not specified.
- **Option Groups**: Primarily used for Oracle and SQL Server specific features.
- **Blue/Green Deployments**: Supported for MySQL and MariaDB. Creates a staging environment for testing updates.
- **Point-in-Time Recovery**: Requires backup_retention_period > 0.

## Architecture

### Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS RDS Instance                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                              RDS Core                                   │  │
│  │  • MySQL, PostgreSQL, MariaDB, Oracle, SQL Server                      │  │
│  │  • Instance class and storage configuration                            │  │
│  │  • Multi-AZ for high availability                                      │  │
│  │  • Encryption at rest (KMS)                                            │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                     │                                         │
│                                     ▼                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   DB Subnet Group    │  │   Parameter Group    │  │   Option Group     │  │
│  │  • Private subnets   │  │  • Engine settings   │  │  • Oracle/SQL Srv  │  │
│  │  • Multi-AZ support  │  │  • Custom params     │  │  • Engine options  │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────┐  │
│  │   Security Group     │  │   Read Replicas      │  │   Secrets Manager  │  │
│  │  • Ingress rules     │  │  • Horizontal scale  │  │  • Master password │  │
│  │  • CIDR/SG sources   │  │  • Cross-AZ          │  │  • Auto rotation   │  │
│  └──────────────────────┘  └──────────────────────┘  └────────────────────┘  │
│                                                                               │
│  ┌──────────────────────┐  ┌──────────────────────────────────────────────┐  │
│  │   Enhanced Monitor   │  │              CloudWatch Alarms               │  │
│  │  • OS-level metrics  │  │  • CPU utilization    • Free storage         │  │
│  │  • IAM role          │  │  • Database connections                      │  │
│  └──────────────────────┘  └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Module Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                         DATABASE/RDS TERRAFORM MODULE                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                 INPUT VARIABLES                                                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │       GENERAL               │   │         ENGINE                  │   │          INSTANCE & STORAGE             │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • name (required)           │   │ • engine (required)             │   │ • instance_class (required)             │  ║
║  │ • tags                      │   │ • engine_major_version          │   │ • allocated_storage (required)          │  ║
║  └─────────────────────────────┘   │ • engine_minor_version          │   │ • max_allocated_storage                 │  ║
║                                    │ • license_model                 │   │ • storage_type                          │  ║
║                                    └─────────────────────────────────┘   │ • iops, storage_throughput              │  ║
║                                                                          │ • storage_encryption_enabled, kms_key_id│  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │      NETWORK                │   │      SECURITY GROUP             │   │       HIGH AVAILABILITY                 │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • vpc_id (required)         │   │ • security_group_creation_enabled         │   │ • multi_az_enabled                      │  ║
║  │ • subnet_ids (required)     │   │ • security_group_id             │   │ • read_replica_creation_enabled                   │  ║
║  │ • port                      │   │ • allowed_security_group_ids    │   │ • read_replica_count                    │  ║
║  │ • public_access_enabled     │   │ • allowed_cidr_blocks           │   │ • read_replica_instance_class           │  ║
║  │ • availability_zone         │   └─────────────────────────────────┘   │ • read_replica_availability_zones       │  ║
║  │ • ca_cert_identifier        │                                         └─────────────────────────────────────────┘  ║
║  └─────────────────────────────┘                                                                                       ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │      AUTHENTICATION         │   │         DATABASE                │   │            BACKUP                       │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • username (required)       │   │ • db_name                       │   │ • backup_retention_period               │  ║
║  │ • password                  │   │ • character_set_name            │   │ • backup_window                         │  ║
║  │ • master_user_password_mgmt │   │ • timezone                      │   │ • snapshot_tag_copying_enabled          │  ║
║  │ • master_user_secret_kms_id │   │ • domain                        │   │ • automated_backups_deletion_enabled    │  ║
║  │ • iam_database_auth_enabled │   │ • domain_iam_role_name          │   │ • snapshot_identifier                   │  ║
║  └─────────────────────────────┘   └─────────────────────────────────┘   │ • final_snapshot_identifier             │  ║
║                                                                          │ • final_snapshot_creation_enabled       │  ║
║                                                                          │ • restore_to_point_in_time              │  ║
║                                                                          └─────────────────────────────────────────┘  ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │      MAINTENANCE            │   │         MONITORING              │   │       CLOUDWATCH ALARMS                 │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • maintenance_window        │   │ • monitoring_interval           │   │ • cloudwatch_alarms_creation_enabled              │  ║
║  │ • minor_version_auto_upgrade_enabled│ • monitoring_role_arn           │   │ • cloudwatch_alarm_cpu_threshold        │  ║
║  │ • major_version_upgrade_enabled│ │ • monitoring_role_creation_enabled        │   │ • cloudwatch_alarm_storage_threshold    │  ║
║  │ • immediate_apply_enabled   │   │ • performance_insights_enabled  │   │ • cloudwatch_alarm_connections_threshold│  ║
║  │ • deletion_protection_enabled       │   │ • perf_insights_retention_period│   │ • cloudwatch_alarm_actions              │  ║
║  └─────────────────────────────┘   │ • perf_insights_kms_key_id      │   │ • cloudwatch_ok_actions                 │  ║
║                                    │ • enabled_cw_logs_exports       │   └─────────────────────────────────────────┘  ║
║                                    └─────────────────────────────────┘                                                 ║
║                                                                                                                        ║
║  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   ┌─────────────────────────────────────────┐  ║
║  │    PARAMETER GROUP          │   │        OPTION GROUP             │   │         BLUE/GREEN                      │  ║
║  ├─────────────────────────────┤   ├─────────────────────────────────┤   ├─────────────────────────────────────────┤  ║
║  │ • parameter_group_creation_enabled    │   │ • option_group_creation_enabled           │   │ • blue_green_update                     │  ║
║  │ • parameter_group_name      │   │ • option_group_name             │   │   └─ enabled                            │  ║
║  │ • parameter_group_family    │   │ • option_group_engine_version   │   └─────────────────────────────────────────┘  ║
║  │ • parameters                │   │ • options                       │                                                 ║
║  └─────────────────────────────┘   └─────────────────────────────────┘                                                 ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                              TERRAFORM RESOURCES                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                      aws_db_subnet_group.this                                                │    ║
║    │  • Creates subnet group from var.subnet_ids for Multi-AZ placement                                          │    ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐            ║
║           │                                               │                                               │            ║
║           ▼                                               ▼                                               ▼            ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │ aws_db_parameter_group.this │    │   aws_db_option_group.this   │    │   aws_security_group.this    │          ║
║    │      (count: 0 or 1)        │    │      (count: 0 or 1)         │    │      (count: 0 or 1)         │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • Engine-specific family    │    │ • Oracle/SQL Server options  │    │ • Ingress from allowed SGs   │          ║
║    │ • Custom parameters         │    │ • S3 integration, STATSPACK  │    │ • Ingress from CIDR blocks   │          ║
║    │ • apply_method per param    │    │ • Engine-specific features   │    │ • Egress all                 │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                           │                                                            ║
║                                                           ▼                                                            ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐    ║
║    │                                         aws_db_instance.this                                                 │    ║
║    │                                            (CORE RESOURCE)                                                   │    ║
║    ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤    ║
║    │                                                                                                              │    ║
║    │  Attributes:                                                                                                 │    ║
║    │  • identifier, engine, engine_version, instance_class                                                        │    ║
║    │  • allocated_storage, max_allocated_storage, storage_type, iops, storage_throughput                          │    ║
║    │  • db_subnet_group_name, vpc_security_group_ids, public_access_enabled, port                                 │    ║
║    │  • multi_az_enabled, availability_zone                                                                       │    ║
║    │  • username, master_user_password_management_enabled, master_user_secret_kms_key_id                          │    ║
║    │  • db_name, parameter_group_name, option_group_name                                                          │    ║
║    │  • storage_encryption_enabled, kms_key_id, iam_database_authentication_enabled                               │    ║
║    │  • backup_retention_period, backup_window, maintenance_window                                                │    ║
║    │  • monitoring_interval, monitoring_role_arn, performance_insights_enabled                                    │    ║
║    │  • enabled_cloudwatch_logs_exports, deletion_protection_enabled, final_snapshot_creation_enabled             │    ║
║    │                                                                                                              │    ║
║    │  ┌─────────────────────────────┐                                                                             │    ║
║    │  │ dynamic "blue_green_update" │  (enabled for MySQL/MariaDB zero-downtime updates)                          │    ║
║    │  └─────────────────────────────┘                                                                             │    ║
║    └──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘    ║
║                                                           │                                                            ║
║           ┌───────────────────────────────────────────────┼───────────────────────────────────────────────┐            ║
║           │                                               │                                               │            ║
║           ▼                                               ▼                                               ▼            ║
║    ┌──────────────────────────────┐    ┌──────────────────────────────┐    ┌──────────────────────────────┐          ║
║    │ aws_db_instance.read_replica│    │   aws_iam_role.monitoring    │    │  aws_cloudwatch_metric_alarm │          ║
║    │      (count: 0 to N)        │    │      (count: 0 or 1)         │    │       (count: 0 or 3)        │          ║
║    ├──────────────────────────────┤    ├──────────────────────────────┤    ├──────────────────────────────┤          ║
║    │ • Async replicas            │    │ • Enhanced Monitoring role   │    │ • CPU utilization alarm      │          ║
║    │ • Cross-AZ placement        │    │ • rds-monitoring-role policy │    │ • Free storage alarm         │          ║
║    │ • Horizontal read scaling   │    │ • AmazonRDSEnhanced...Access │    │ • Database connections alarm │          ║
║    └──────────────────────────────┘    └──────────────────────────────┘    └──────────────────────────────┘          ║
║                                                                                                                        ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                                         │
                                                         ▼
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                                   OUTPUTS                                                              ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         RDS INSTANCE                    │   │            CONNECTION                   │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • db_instance_id                        │   │ • endpoint (address:port)               │                            ║
║  │ • db_instance_arn                       │   │ • address                               │                            ║
║  │ • db_instance_identifier                │   │ • port                                  │                            ║
║  │ • db_instance_resource_id               │   │ • hosted_zone_id                        │                            ║
║  │ • db_instance_status                    │   └─────────────────────────────────────────┘                            ║
║  │ • db_instance_availability_zone         │                                                                          ║
║  └─────────────────────────────────────────┘   ┌─────────────────────────────────────────┐                            ║
║                                                │         ENGINE & DATABASE               │                            ║
║  ┌─────────────────────────────────────────┐   ├─────────────────────────────────────────┤                            ║
║  │         READ REPLICAS                   │   │ • engine                                │                            ║
║  ├─────────────────────────────────────────┤   │ • engine_version_actual                 │                            ║
║  │ • read_replica_identifiers              │   │ • db_name                               │                            ║
║  │ • read_replica_endpoints                │   │ • username                              │                            ║
║  │ • read_replica_arns                     │   │ • master_user_secret_arn                │                            ║
║  └─────────────────────────────────────────┘   └─────────────────────────────────────────┘                            ║
║                                                                                                                        ║
║  ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                            ║
║  │         SECURITY GROUP                  │   │      SUBNET & PARAMETER GROUPS          │                            ║
║  ├─────────────────────────────────────────┤   ├─────────────────────────────────────────┤                            ║
║  │ • security_group_id                     │   │ • db_subnet_group_name                  │                            ║
║  │ • security_group_arn                    │   │ • db_subnet_group_arn                   │                            ║
║  └─────────────────────────────────────────┘   │ • db_parameter_group_name               │                            ║
║                                                │ • db_parameter_group_arn                │                            ║
║  ┌─────────────────────────────────────────┐   │ • db_option_group_name                  │                            ║
║  │         MONITORING                      │   │ • db_option_group_arn                   │                            ║
║  ├─────────────────────────────────────────┤   └─────────────────────────────────────────┘                            ║
║  │ • enhanced_monitoring_iam_role_arn      │                                                                          ║
║  │ • cloudwatch_alarm_arns                 │                                                                          ║
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
║                                        └────────────┬────────────┘                                                     ║
║                                                     │                                                                  ║
║                                                     ▼                                                                  ║
║  var.name ─────────────────────────────► aws_db_subnet_group.this                                                     ║
║  var.tags ─────────────────────────────►         │                                                                    ║
║                                                  │                                                                    ║
║  var.security_group_creation_enabled ────────────► aws_security_group.this[0]                                                   ║
║  var.allowed_security_group_ids ───────►         │                                                                    ║
║  var.allowed_cidr_blocks ──────────────►         │                                                                    ║
║                                                  │                                                                    ║
║  var.parameter_group_creation_enabled ───────────► aws_db_parameter_group.this[0]                                               ║
║  var.parameter_group_family ───────────►         │                                                                    ║
║  var.parameters ───────────────────────►         │                                                                    ║
║                                                  │                                                                    ║
║  var.option_group_creation_enabled ──────────────► aws_db_option_group.this[0]                                                  ║
║  var.options ──────────────────────────►         │                                                                    ║
║                                                  │                                                                    ║
║                                                  ▼                                                                    ║
║              ┌───────────────────────────────────────────────────────────────────────────────────┐                     ║
║  var.engine ────────────────────────────►│                                                       │                     ║
║  local.engine_version ───────────────────►│                                                       │                     ║
║  var.instance_class ────────────────────►│                                                       │                     ║
║  var.allocated_storage ─────────────────►│                                                       │                     ║
║  var.storage_type ──────────────────────►│                                                       │                     ║
║  var.iops ──────────────────────────────►│                                                       │                     ║
║  var.storage_encryption_enabled ────────►│                    aws_db_instance.this               │                     ║
║  var.kms_key_id ────────────────────────►│                                                       │                     ║
║  var.multi_az_enabled ──────────────────►│                                                       │                     ║
║  var.username ──────────────────────────►│                                                       │                     ║
║  var.master_user_password_management_enabled ─►│                                                  │                     ║
║  var.backup_retention_period ───────────►│                                                       │                     ║
║  var.deletion_protection_enabled ───────────────►│                                                       │                     ║
║  var.performance_insights_enabled ──────►│                                                       │                     ║
║  var.blue_green_update ─────────────────►│                                                       │                     ║
║              └───────────────────────────────────────────────────┬───────────────────────────────┘                     ║
║                                                                  │                                                     ║
║           ┌──────────────────────────────────────────────────────┼──────────────────────────────────────┐              ║
║           │                                                      │                                      │              ║
║           ▼                                                      ▼                                      ▼              ║
║  var.read_replica_creation_enabled                          var.monitoring_role_creation_enabled           var.cloudwatch_alarms_creation_enabled   ║
║  var.read_replica_count                           var.monitoring_interval              var.cloudwatch_alarm_*         ║
║  var.read_replica_instance_class                           │                                      │                   ║
║           │                                                │                                      │                   ║
║           ▼                                                ▼                                      ▼                   ║
║  aws_db_instance.read_replica[*]               aws_iam_role.monitoring[0]        aws_cloudwatch_metric_alarm.*[0]     ║
║                                                                                                                        ║
║           │                                                │                                      │                   ║
║           └──────────────────────────────────────────────────────┼──────────────────────────────────────┘              ║
║                                                                  │                                                     ║
║                                                                  ▼                                                     ║
║                                                           MODULE OUTPUTS                                               ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### Resource Summary

| Resource | Count Logic | Purpose |
|----------|-------------|---------|
| `aws_db_subnet_group` | 1 | Subnet group for Multi-AZ placement |
| `aws_db_instance` | 1 | Primary RDS database instance |
| `aws_db_instance` (replica) | 0 to N | Read replicas for horizontal scaling |
| `aws_security_group` | 0 or 1 | Security group (if `security_group_creation_enabled = true`) |
| `aws_db_parameter_group` | 0 or 1 | Custom parameters (if `parameter_group_creation_enabled = true`) |
| `aws_db_option_group` | 0 or 1 | Engine options (if `option_group_creation_enabled = true`) |
| `aws_iam_role` | 0 or 1 | Enhanced Monitoring role (if `monitoring_role_creation_enabled = true`) |
| `aws_iam_role_policy_attachment` | 0 or 1 | Monitoring role policy attachment |
| `aws_cloudwatch_metric_alarm` | 0 or 3 | CPU, storage, connections alarms (if `cloudwatch_alarms_creation_enabled = true`) |
