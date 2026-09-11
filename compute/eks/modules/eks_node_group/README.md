# EKS Node Group

Internal child module of [`compute/eks`](../..) — consumed via the composite only; not independently versioned or published.

Provisions one EKS managed node group, plus its IAM node role (optional) and a
custom launch template (optional, only when the caller customizes anything
beyond AMI / instance shape).

Instantiate this module once per node group. Use a small on-demand "system"
group for control-plane-adjacent workloads (Karpenter, the LB Controller,
CoreDNS, metrics-server) and let Karpenter handle elasticity for everything
else.

## Usage

Prefer the [`compute/eks`](../..) composite. This module is nested under
`compute/eks/modules/` and is not independently published.

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| opentofu/terraform | >= 1.10.0  |
| aws                | >= 6.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster the node group joins. | `string` | n/a | yes |
| name | Node group name (unique within cluster). | `string` | n/a | yes |
| subnet_ids | Subnets to launch nodes in. | `list(string)` | n/a | yes |
| capacity_type | `ON_DEMAND`, `SPOT`, or `CAPACITY_BLOCK`. | `string` | `"ON_DEMAND"` | no |
| instance_types | Allowed instance types. | `list(string)` | `["t3.medium"]` | no |
| ami_type | AMI type managed by EKS. | `string` | `"AL2023_x86_64_STANDARD"` | no |
| kubernetes_version | Pin node version (defaults to cluster). | `string` | `null` | no |
| min_size / desired_size / max_size | Scaling bounds. | `number` | 1/1/3 | no |
| max_unavailable | Max nodes unavailable during update (mutually exclusive with percentage). | `number` | `null` | no |
| max_unavailable_percentage | Max % of nodes unavailable during update. | `number` | `33` | no |
| version_force_update_enabled | Ignore PDBs during version updates. | `bool` | `false` | no |
| labels | Kubernetes labels. | `map(string)` | `{}` | no |
| taints | Kubernetes taints. | `list(object)` | `[]` | no |
| disk_size / disk_type / disk_iops / disk_throughput | Root volume tuning (triggers launch template). | `number/string/number/number` | `null` | no |
| ebs_kms_key_arn | Encrypt root volume with this KMS key (triggers launch template). | `string` | `null` | no |
| user_data | Custom user data, base64-encoded internally and merged by EKS with its own bootstrap user data (triggers launch template). Format depends on `ami_type` — see [User data format](#user-data-format). | `string` | `null` | no |
| security_group_ids | Extra SGs on node ENIs (triggers launch template). | `list(string)` | `[]` | no |
| detailed_monitoring_enabled | Enable EC2 1-minute monitoring. | `bool` | `false` | no |
| metadata_http_tokens | IMDSv2 enforcement. | `string` | `"required"` | no |
| metadata_http_put_response_hop_limit | IMDS hop limit. | `number` | `2` | no |
| node_role_arn | BYO node role. When null, module creates one. | `string` | `null` | no |
| node_role_additional_managed_policy_arns | Extra managed policies on the module-created role. | `list(string)` | `[]` | no |
| node_role_additional_inline_policy_statements | Extra inline statements on the module-created role. | `list(object)` | `[]` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| partition | AWS partition used to build managed policy ARNs. Pass from the caller when instantiating with `depends_on` so ARNs are known at plan time; resolved via data source when null. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| node_group_arn / node_group_id / node_group_name | Node group identifiers. |
| node_group_status | EKS-reported status. |
| node_group_resources | Underlying ASG / remote access SG. |
| node_role_arn / node_role_name | IAM role used by nodes. |
| launch_template_id / launch_template_arn / launch_template_latest_version | Launch template (null when EKS-default). |
| aws_account_id / region | Account & region info. |

## User data format

`user_data` is written verbatim into the launch template as
`base64encode(var.user_data)`. The module does not wrap, template, or append
anything to it, and the launch template deliberately never sets `image_id` —
the AMI comes from the node group's `ami_type`.

Because no AMI ID is specified, EKS **merges** its own generated bootstrap user
data with the value you supply, and that merge only works when your value is in
the format the AMI family expects. A bare `#!/bin/bash` script is *not* valid
for the default `AL2023_x86_64_STANDARD` AMI type and will leave nodes unable to
join the cluster.

Consequences of the merge, for every AMI type:

- Don't call `bootstrap.sh`, `nodeadm`, or `Start-EKSBootstrap.ps1` yourself — EKS supplies those.
- Don't start or reconfigure `kubelet` from `user_data`. Use this module's `labels` / `taints` inputs instead.
- Cluster metadata (`name`, `apiServerEndpoint`, `certificateAuthority`, `cidr`) comes from the EKS-merged part; don't repeat it.

| `ami_type` | Required format | Notes |
|------------|-----------------|-------|
| `AL2_*` | MIME multi-part archive | Shell commands go in a `Content-Type: text/x-shellscript` part. |
| `AL2023_*` (default) | MIME multi-part archive | Shell commands go in a `text/x-shellscript` part; node/kubelet settings go in an `application/node.eks.aws` part holding a `node.eks.aws/v1alpha1` `NodeConfig` document. |
| `BOTTLEROCKET_*` | TOML settings | Merged with the EKS-provided settings, and your keys win. Formatting isn't preserved, and EKS doesn't accept every valid TOML construct (no quoted keys within quoted keys, escaped quotes in values, or mixed-type arrays). |
| `WINDOWS_*` | PowerShell | Your commands run first, then the EKS-managed commands, all inside a single `<powershell></powershell>` tag. |
| `CUSTOM` | n/a | Requires an AMI ID in the launch template, which this module does not expose. |

AL2023 — pass the whole MIME document as the value (typically via `file()` so
boundary lines aren't reindented):

```
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
dnf install -y htop

--BOUNDARY
Content-Type: application/node.eks.aws

apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  kubelet:
    config:
      shutdownGracePeriod: 30s

--BOUNDARY--
```

```hcl
user_data = file("${path.module}/al2023-user-data.txt")
```

Bottlerocket:

```
[settings.kubernetes.system-reserved]
cpu = "10m"
memory = "100Mi"
```

Reference: [Customize managed nodes with launch templates — Amazon EC2 user data](https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html#launch-template-user-data).

## Notes

- The default node role grants `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryPullOnly`. Upgrading replaces the broader ECR `ReadOnly` attachment with `PullOnly` without replacing nodes. Explicit additional policies remain supported.
- `desired_size` is honored on create and ignored thereafter via `lifecycle.ignore_changes` so an autoscaler can manage capacity without drifting against terraform state. Use `min_size` / `max_size` to constrain it.
- A launch template is only created when at least one of `disk_size`, `disk_type`, `disk_iops`, `disk_throughput`, `ebs_kms_key_arn`, `user_data`, `security_group_ids`, `detailed_monitoring_enabled`, or non-default IMDS settings is supplied. Otherwise EKS uses its internal default template (which we cannot modify directly).
- The default node role does not grant Systems Manager access. If Session Manager is required, explicitly include `AmazonSSMManagedInstanceCore` in `node_role_additional_managed_policy_arns`. Upgrading detaches the previously default policy unless it is explicitly included; it does not replace nodes.
