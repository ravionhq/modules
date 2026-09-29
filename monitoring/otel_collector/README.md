# OpenTelemetry Collector Module

Runs the [AWS Distro for OpenTelemetry](https://aws-otel.github.io/) collector as an ECS service on Fargate inside a VPC. It receives OTLP over gRPC (4317) and HTTP (4318) at a private Cloud Map hostname, `otlp.<name>.internal`, and exports traces to AWS X-Ray. An optional metrics pipeline publishes OTLP metrics to CloudWatch as embedded metric format logs.

## Features

- OTLP/gRPC on 4317 and OTLP/HTTP on 4318, reachable only from the security groups you allow. The tasks have no public IP, and their only egress is HTTPS.
- Traces go through a memory limiter and a batch processor to the `awsxray` exporter. The exporter accepts random W3C trace IDs, so OpenTelemetry SDKs need no X-Ray ID generator.
- Optional metrics pipeline (`metrics_enabled`) to the `awsemf` exporter, off by default.
- A least-privilege task role: `xray:PutTraceSegments` and `xray:PutTelemetryRecords`, plus stream creation and writes to the module's own metric log group while metrics are enabled.
- Collector configuration rendered from `templates/collector.yaml.tftpl` and passed through `AOT_CONFIG_CONTENT`. A configuration change is a new task definition revision.
- A container health check through the image's `/healthcheck` binary. Cloud Map drops unhealthy tasks from DNS, and the deployment circuit breaker rolls back a revision the collector cannot start with.
- A dedicated Fargate cluster, and a CloudWatch log group for the collector's own logs with configurable retention.

## Usage

```hcl
module "otel_collector" {
  source = "git::https://github.com/ravionhq/modules.git//monitoring/otel_collector?ref=rvn-aws-otel-collector@0.1.0"

  name       = "shared-otel"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]

  # Security groups of the services that send telemetry.
  allowed_security_group_ids = [aws_security_group.app.id]

  desired_count = 2
}
```

Point the senders at the outputs:

```hcl
environment = [
  { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = module.otel_collector.otlp_grpc_endpoint },
  { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "grpc" },
]
```

### CloudWatch metrics

```hcl
module "otel_collector" {
  # ...
  metrics_enabled   = true
  metrics_namespace = "Checkout"
}
```

Every distinct metric and attribute combination becomes a billed CloudWatch custom metric. While metrics are disabled, the collector rejects OTLP metric exports.

## Networking requirements

- The subnets need outbound HTTPS to X-Ray, CloudWatch Logs and Amazon ECR Public, through a NAT gateway or VPC endpoints.
- The VPC needs DNS support and DNS hostnames enabled so that senders resolve `otlp.<name>.internal`. Only this VPC resolves the name. To reach the collector from another VPC, associate that VPC with `service_discovery_hosted_zone_id`.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the cluster, service and task family, and prefix of every other resource. 1-54 lowercase letters, digits or hyphens. | `string` | n/a | yes |
| vpc_id | VPC the collector runs in and whose DNS resolves its hostname. | `string` | n/a | yes |
| subnet_ids | Subnets the collector tasks run in. | `list(string)` | n/a | yes |
| allowed_security_group_ids | Security groups allowed to send OTLP on 4317 and 4318. | `list(string)` | `[]` | no |
| image | AWS Distro for OpenTelemetry collector image. | `string` | `"public.ecr.aws/aws-observability/aws-otel-collector:v0.50.0"` | no |
| task_cpu | CPU units for each task. | `number` | `512` | no |
| task_memory | Memory in MiB for each task. | `number` | `1024` | no |
| cpu_architecture | `ARM64` or `X86_64`. | `string` | `"ARM64"` | no |
| desired_count | Number of collector tasks. | `number` | `1` | no |
| metrics_enabled | Accept OTLP metrics and publish them to CloudWatch. | `bool` | `false` | no |
| metrics_namespace | CloudWatch namespace for metrics. Null derives it from each sender's `service.namespace` and `service.name`. | `string` | `null` | no |
| log_retention_days | Retention for the collector's logs and the metric logs. 0 keeps them indefinitely. | `number` | `30` | no |
| region | AWS region. Defaults to the provider region. | `string` | `null` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| hostname | The collector's private DNS name. |
| otlp_grpc_endpoint | `http://<hostname>:4317`. |
| otlp_http_endpoint | `http://<hostname>:4318`. Senders append `/v1/traces` or `/v1/metrics`. |
| otlp_grpc_port | 4317. |
| otlp_http_port | 4318. |
| security_group_id | The collector's security group. |
| service_discovery_namespace_id | The Cloud Map private DNS namespace. |
| service_discovery_hosted_zone_id | The Route 53 private hosted zone behind the namespace. |
| cluster_arn | The collector's ECS cluster ARN. |
| cluster_name | The collector's ECS cluster name. |
| service_name | The collector's ECS service name. |
| task_definition_arn | The current task definition revision. |
| task_role_arn | The role the collector calls AWS with. |
| task_role_name | The task role's name, for attaching further policies. |
| log_group_name | The collector's own log group. |
| log_stream_prefix | The prefix of the collector's log streams. |
| metrics_log_group_name | The metric log group, or null while metrics are disabled. |
| region | The region the collector runs in and exports to. |

## Testing

```bash
tofu init -backend=false
tofu test
```
