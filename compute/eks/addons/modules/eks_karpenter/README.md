# EKS Karpenter (IAM + Queue helper)

Internal child module of [`compute/eks/addons`](../..) — consumed via the addons stack only; not independently versioned or published.

Provisions everything Karpenter needs on the AWS side so a consumer can
`helm install` the controller without writing IAM by hand:

- A controller IAM role trusted by EKS Pod Identity (`pods.eks.amazonaws.com`),
  with the inline policies from upstream's CloudFormation translated into HCL.
- An EKS Pod Identity association binding that role to the controller's
  service account.
- A node IAM role + instance profile for the EC2 instances Karpenter launches,
  plus an `EC2_LINUX` access entry so kubelets can register against an
  `authentication_mode = API` cluster.
- An SQS interruption queue + EventBridge rules for spot interruption,
  rebalance recommendations, instance state changes, capacity reservation
  interruptions, and AWS Health events.

The node role does not grant Systems Manager access by default. Session Manager
permissions can be supplied through `node_role_additional_managed_policy_arns`.
Upgrading detaches the previously default `AmazonSSMManagedInstanceCore` policy
unless explicitly included; it does not replace nodes.

The Helm install of Karpenter itself is done by the parent addons stack —
its charts consume the outputs from this module:

```
settings.clusterName            = <your cluster>
settings.interruptionQueue      = <output: interruption_queue_name>
serviceAccount.name             = <var.controller_service_account, default "karpenter">
serviceAccount.namespace        = <var.controller_namespace, default "kube-system">
```

And in your `EC2NodeClass`:

```
spec.instanceProfile = <output: node_instance_profile_name>
```

## Prerequisites

- The cluster has `eks-pod-identity-agent` running. The `eks_cluster` module installs it by default; otherwise install it yourself.
- The cluster's `authentication_mode` is `API` (or `API_AND_CONFIG_MAP`). Required for the EC2_LINUX access entry to take effect.

## Usage

Prefer the [`compute/eks/addons`](../..) stack. This module is nested
under `compute/eks/addons/modules/` and is not independently published.

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| opentofu/terraform | >= 1.10.0  |
| aws                | >= 6.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | EKS cluster name (used to scope IAM and tag events). | `string` | n/a | yes |
| controller_namespace | Namespace of the Karpenter controller SA. | `string` | `"kube-system"` | no |
| controller_service_account | Karpenter controller SA name. | `string` | `"karpenter"` | no |
| node_role_additional_managed_policy_arns | Extra managed policies for Karpenter-launched nodes. | `list(string)` | `[]` | no |
| interruption_queue_name | Override the default queue name (`karpenter-<cluster>`). | `string` | `null` | no |
| interruption_queue_message_retention_seconds | SQS retention. AWS-recommended default 300s. | `number` | `300` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| partition | AWS partition used to build managed policy ARNs. Pass from the caller when instantiating with `depends_on` so ARNs are known at plan time; resolved via data source when null. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| controller_role_arn / controller_role_name | Karpenter controller IAM role. |
| node_role_arn / node_role_name | IAM role on Karpenter-launched nodes. |
| node_instance_profile_name / node_instance_profile_arn | Instance profile (use in EC2NodeClass). |
| interruption_queue_name / interruption_queue_arn / interruption_queue_url | SQS queue. |
| aws_account_id / region | Account & region info. |

## Notes

- The controller IAM policy mirrors the upstream Karpenter CloudFormation template at `aws/karpenter-provider-aws/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml`. When Karpenter publishes a new policy version, update `controller_policies.tf` accordingly.
- The node role uses `AmazonEC2ContainerRegistryPullOnly` rather than `AmazonEC2ContainerRegistryReadOnly` to match the principle of least privilege the upstream chose. If your nodes need to push images (uncommon), attach an extra policy via `var.node_role_additional_managed_policy_arns`.
- The queue policy denies non-TLS traffic and only accepts `SendMessage` from EventBridge / SQS service principals, matching the upstream pattern.
