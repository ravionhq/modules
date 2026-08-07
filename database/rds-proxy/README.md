# RDS Proxy

Creates an Amazon RDS Proxy that sits in front of an RDS instance or Aurora cluster to provide connection pooling, improved failover handling, and optional IAM authentication for database connections.

The module creates:

- An RDS Proxy with Secrets Manager based authentication
- The default proxy target group with configurable connection pool settings
- A proxy target registration for an RDS instance or Aurora cluster
- An IAM role allowing the proxy to read credentials from Secrets Manager (optional, with least-privilege access to only the referenced secrets)
- A security group for the proxy (optional)

This module can be used standalone, or deployed automatically by the `database/rds` and `database/aurora` modules by setting `proxy_creation_enabled = true` on those modules.

## Usage

### Standalone, in front of an existing RDS instance

```hcl
module "rds_proxy" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/rds-proxy?ref=v1.0.0"

  name          = "myapp"
  engine_family = "POSTGRESQL"

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-11111111", "subnet-22222222"]

  db_instance_identifier = "myapp-db"

  auth = [
    {
      secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:myapp-db-credentials-AbCdEf"
    }
  ]

  allowed_security_group_ids = ["sg-12345678"]

  tags = {
    Environment = "production"
  }
}
```

### Standalone, in front of an Aurora cluster

```hcl
module "rds_proxy" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/rds-proxy?ref=v1.0.0"

  name          = "myapp"
  engine_family = "MYSQL"

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-11111111", "subnet-22222222"]

  db_cluster_identifier = "myapp-aurora"

  auth = [
    {
      secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:myapp-db-credentials-AbCdEf"
      iam_auth   = "REQUIRED"
    }
  ]

  allowed_security_group_ids = ["sg-12345678"]
}
```

### Via the rds or aurora modules

```hcl
module "rds" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/rds?ref=v1.0.0"

  # ... regular rds inputs ...

  proxy_creation_enabled = true
}
```

When deployed through the `rds` or `aurora` modules, the proxy authenticates with the managed master user secret (requires `master_user_password_management_enabled = true`, the default) or with explicitly provided `proxy_auth_secret_arns`. The database security group automatically allows ingress from the proxy security group, and the proxy security group allows ingress from the module's `allowed_security_group_ids` and `allowed_cidr_blocks`.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module. Also used as the DB proxy name. | `string` | n/a | yes |
| engine_family | The kind of database engine the proxy connects to: MYSQL (also used for MariaDB), POSTGRESQL, or SQLSERVER. | `string` | n/a | yes |
| vpc_id | The ID of the VPC where the proxy will be created. | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the proxy (minimum 2, in different AZs). | `list(string)` | n/a | yes |
| auth | List of authentication configurations. Each entry references a Secrets Manager secret and supports optional description, username, iam_auth (DISABLED, REQUIRED, ENABLED), and client_password_auth_type. | `list(object)` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| tls_requirement_enabled | Require TLS for connections to the proxy. | `bool` | `true` | no |
| debug_logging_enabled | Log detailed connection information, including SQL statements, to CloudWatch Logs. | `bool` | `false` | no |
| idle_client_timeout | Seconds a client connection can be idle before the proxy disconnects it (1-28800). | `number` | `1800` | no |
| secret_kms_key_arns | KMS key ARNs used to encrypt the auth secrets (needed for customer-managed keys only). | `list(string)` | `[]` | no |
| db_instance_identifier | RDS instance identifier to register as the proxy target (exactly one of db_instance_identifier or db_cluster_identifier). | `string` | `null` | no |
| db_cluster_identifier | Aurora cluster identifier to register as the proxy target (exactly one of db_instance_identifier or db_cluster_identifier). | `string` | `null` | no |
| connection_borrow_timeout | Seconds the proxy waits for an available connection in the pool. | `number` | `120` | no |
| init_query | SQL statements the proxy runs when opening each new database connection. | `string` | `null` | no |
| max_connections_percent | Max connection pool size as a percentage of the database max_connections (1-100). | `number` | `100` | no |
| max_idle_connections_percent | Max idle connections as a percentage of the database max_connections (0-100). | `number` | `50` | no |
| session_pinning_filters | Session pinning filters. Valid value: EXCLUDE_VARIABLE_SETS. | `list(string)` | `[]` | no |
| port | The port used for security group rules (defaults per engine_family: 3306, 5432, 1433). | `number` | `null` | no |
| security_group_creation_enabled | Whether to create a security group for the proxy. | `bool` | `true` | no |
| security_group_id | Existing security group ID to use when creation is disabled. | `string` | `null` | no |
| allowed_security_group_ids | Security group IDs allowed to connect to the proxy. | `list(string)` | `[]` | no |
| allowed_cidr_blocks | CIDR blocks allowed to connect to the proxy. | `list(string)` | `[]` | no |
| iam_role_creation_enabled | Whether to create the IAM role the proxy uses to read secrets. | `bool` | `true` | no |
| iam_role_arn | Existing IAM role ARN to use when role creation is disabled. | `string` | `null` | no |
| region | AWS region. When null, the provider's configured region is used. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| proxy_id | The ID of the RDS Proxy. |
| proxy_arn | The ARN of the RDS Proxy. |
| proxy_name | The name of the RDS Proxy. |
| endpoint | The endpoint that applications use to connect through the proxy. |
| port | The port on which the proxy accepts connections. |
| default_target_group_name | The name of the default proxy target group. |
| default_target_group_arn | The ARN of the default proxy target group. |
| iam_role_arn | The ARN of the IAM role the proxy uses to read Secrets Manager secrets. |
| security_group_id | The security group ID. |
| security_group_arn | The security group ARN. |
| aws_account_id | The AWS account ID where the resources are deployed. |
| region | The AWS region where the resources are deployed. |

## Security Considerations

- **Secrets Manager**: The proxy authenticates to the database using Secrets Manager secrets; no plaintext credentials.
- **Least privilege IAM**: The created IAM role can only read the specific secrets referenced in `auth` (plus `kms:Decrypt` scoped to the provided keys via Secrets Manager).
- **TLS**: Required by default for client connections to the proxy.
- **VPC only**: The proxy is deployed within your VPC; the security group only allows the sources you list.

## Notes

- RDS Proxy supports MySQL, MariaDB (via the MYSQL engine family), PostgreSQL, and SQL Server. Oracle engines are not supported.
- Registering an Aurora cluster as a proxy target requires the cluster to have at least one instance.
- The secrets referenced in `auth` must be in the same region as the proxy.
