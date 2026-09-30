# Prometheus Workspace Module

Creates an [Amazon Managed Service for Prometheus](https://aws.amazon.com/prometheus/) workspace: a Prometheus-compatible metrics store that senders remote-write to and Grafana queries, both signed with SigV4. The workspace has its own lifecycle, so its metric history outlives the collectors that write to it and the dashboards that read it.

## Features

- A workspace with an alias and a configurable retention period, 150 days by default.
- Optional encryption with a customer managed KMS key.
- Outputs for both sides: `remote_write_url` for senders, `query_url` for Grafana, and `workspace_arn` for scoping `aps:RemoteWrite` and `aps:QueryMetrics` permissions to this workspace.

## Usage

```hcl
module "prometheus_workspace" {
  source = "git::https://github.com/ravionhq/modules.git//monitoring/prometheus_workspace?ref=rvn-aws-prometheus@0.1.0"

  name                     = "shared-metrics"
  retention_period_in_days = 90
}
```

Send an OpenTelemetry collector's metrics to it:

```hcl
module "otel_collector" {
  # ...
  metrics_enabled             = true
  metrics_destination         = "prometheus"
  prometheus_remote_write_url = module.prometheus_workspace.remote_write_url
  prometheus_workspace_arn    = module.prometheus_workspace.workspace_arn
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Alias of the workspace. 1-100 letters, digits, underscores, periods or hyphens. | `string` | n/a | yes |
| retention_period_in_days | Days the workspace keeps samples, 1-1095. | `number` | `150` | no |
| kms_key_arn | Customer managed KMS key that encrypts the workspace. Null uses an AWS owned key. Changing it replaces the workspace and its data. | `string` | `null` | no |
| region | AWS region. Defaults to the provider region. | `string` | `null` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| workspace_id | The workspace ID. |
| workspace_arn | The workspace ARN. |
| query_url | The Prometheus-compatible query endpoint, for a Grafana data source with SigV4 authentication. |
| remote_write_url | The remote write endpoint, for senders signing with SigV4. |
| retention_period_in_days | Days the workspace keeps samples. |
| region | The region the workspace is in. |

## Testing

```bash
tofu init -backend=false
tofu test
```
