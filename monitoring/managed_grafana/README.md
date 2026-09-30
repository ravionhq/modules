# Managed Grafana Module

Creates an [Amazon Managed Grafana](https://aws.amazon.com/grafana/) workspace, the IAM role it reads AWS data with, and its AWS X-Ray, CloudWatch, Amazon Managed Service for Prometheus and Loki data sources, optionally connected to a VPC for data sources reachable only inside it. Users sign in through IAM Identity Center or a SAML 2.0 identity provider.

## Features

- A workspace on a chosen Grafana version with unified alerting on, reading its own account through a customer managed role.
- The X-Ray data source plugin installed from the workspace's plugin catalog. Amazon Managed Grafana installs catalog plugins only while plugin management is on, so `xray_enabled` turns it on.
- IAM Identity Center sign-in with Admin, Editor and Viewer roles assigned by user and group name, or SAML sign-in with role values.
- Data sources with fixed UIDs (`aws-xray`, `aws-cloudwatch`, `amazon-prometheus`, `loki`), kept in line with the module's settings on every apply that changes them.
- An optional VPC connection with a security group of its own that lets HTTPS out. AWS routes every query through the VPC once connected, AWS data sources included, so its private subnets need a NAT gateway or VPC endpoints.
- A read-only role: CloudWatch metrics and logs and X-Ray traces while those data sources are on, and `aps:QueryMetrics`, `aps:GetSeries`, `aps:GetLabels` and `aps:GetMetricMetadata` on the one Prometheus workspace.

## Usage

```hcl
module "grafana" {
  source = "git::https://github.com/ravionhq/modules.git//monitoring/managed_grafana?ref=rvn-aws-managed-grafana@0.1.0"

  name                   = "observability"
  identity_center_region = "us-east-1"
  admin_user_names       = ["jane@example.com"]

  data_source_region                 = module.otel_collector.region
  cloudwatch_default_log_group_names = [module.otel_collector.otlp_log_group_name]
  prometheus_query_url               = module.prometheus_workspace.query_url
  prometheus_workspace_arn           = module.prometheus_workspace.workspace_arn
}
```

### SAML

```hcl
module "grafana" {
  # ...
  authentication          = "saml"
  saml_idp_metadata_url   = "https://idp.example.com/app/metadata"
  saml_role_assertion     = "groups"
  saml_admin_role_values  = ["grafana-admins"]
  saml_editor_role_values = ["grafana-editors"]
}
```

## How data sources are written

Amazon Managed Grafana has no AWS API for data sources. During apply, `scripts/provision_data_sources.py` finds or creates a Grafana Admin service account named `<name>-data-sources`, mints it a token that expires in 15 minutes, creates or updates each wanted data source by UID through the workspace's Grafana API, deletes the module-owned UIDs no longer wanted, and deletes the token. It runs again whenever the wanted data sources, the workspace or the script change. The service account is not a Terraform resource: reading one needs `grafana:ListWorkspaceServiceAccounts`, which read-only plan credentials do not have. The Terraform runner needs the AWS CLI and Python 3.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

IAM Identity Center sign-in needs IAM Identity Center enabled in the AWS organization's management account.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Workspace name. 1-55 letters, digits, periods, underscores, tildes or hyphens. | `string` | n/a | yes |
| description | Workspace description. | `string` | `null` | no |
| grafana_version | Grafana version. | `string` | `"12.4"` | no |
| plugin_admin_enabled | Let admins manage plugins. Always on while `xray_enabled` is true. | `bool` | `false` | no |
| authentication | `iam_identity_center` or `saml`. | `string` | `"iam_identity_center"` | no |
| identity_center_region | Region of the IAM Identity Center instance. Null uses the workspace's region. | `string` | `null` | no |
| admin_user_names, editor_user_names, viewer_user_names | IAM Identity Center user names per Grafana role. | `list(string)` | `[]` | no |
| admin_group_names, editor_group_names, viewer_group_names | IAM Identity Center group display names per Grafana role. | `list(string)` | `[]` | no |
| saml_idp_metadata_url, saml_idp_metadata_xml | Identity provider metadata. One is required for SAML. | `string` | `null` | no |
| saml_role_assertion | Assertion attribute carrying roles. | `string` | `"role"` | no |
| saml_admin_role_values, saml_editor_role_values | Role values per Grafana role. | `list(string)` | `[]` | no |
| saml_login_assertion, saml_email_assertion, saml_name_assertion, saml_org_assertion | Other assertion attributes. | `string` | `null` | no |
| saml_allowed_organizations | Organizations allowed to sign in. | `list(string)` | `[]` | no |
| saml_login_validity_minutes | Minutes a sign-in stays valid. | `number` | `1440` | no |
| data_source_region | Default region of the X-Ray and CloudWatch data sources. Null uses the workspace's region. | `string` | `null` | no |
| xray_enabled | Add the X-Ray data source. | `bool` | `true` | no |
| cloudwatch_enabled | Add the CloudWatch data source. | `bool` | `true` | no |
| cloudwatch_default_log_group_names | Log groups CloudWatch selects by default. | `list(string)` | `[]` | no |
| prometheus_query_url | Query URL of a Prometheus workspace to add. | `string` | `null` | no |
| prometheus_workspace_arn | ARN of that Prometheus workspace. | `string` | `null` | no |
| loki_query_url | Base URL of a Loki query API to add, reached from the VPC connection. | `string` | `null` | no |
| vpc_id | VPC to connect the workspace to. Null connects none. | `string` | `null` | no |
| vpc_subnet_ids | Private subnets in at least two Availability Zones for the VPC connection. | `list(string)` | `[]` | no |
| vpc_security_group_ids | Security groups the VPC connection carries beside the module's own, at most four. | `list(string)` | `[]` | no |
| region | AWS region. Defaults to the provider region. | `string` | `null` | no |
| tags | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| workspace_id | The workspace ID. |
| workspace_arn | The workspace ARN. |
| url | The workspace's sign-in URL. |
| grafana_version | The Grafana version the workspace runs. |
| role_arn | The role the workspace reads AWS data with. |
| role_name | The role's name, for attaching further read policies. |
| data_source_uids | UIDs of the data sources the module manages. |
| region | The region the workspace is in. |
| security_group_id | The workspace's security group on its VPC connection, or null without one. |

## Testing

```bash
tofu init -backend=false
tofu test
```

The tests plan only: an apply would write data sources to a real workspace.
