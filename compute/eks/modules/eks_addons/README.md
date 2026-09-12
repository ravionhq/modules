# EKS Add-ons (post-compute)

Internal child module of [`compute/eks`](../..) — consumed via the composite only; not independently versioned or published.

Installs **Deployment-kind** EKS add-ons whose pods require schedulable compute:

- `coredns` (always)

DaemonSet-kind add-ons (`vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`)
remain in `compute/eks/modules/eks_cluster`. Optional add-ons (EBS CSI,
Container Insights, Karpenter) live in the separately deployed
[`compute/eks/addons`](../../addons) stack.

> **Ordering contract (required):** Apply this module **only after** at least one
> node group or Fargate profile exists on the cluster. CoreDNS is a
> Deployment — without schedulable compute its pods never start, the add-on
> stays `DEGRADED`, and the apply times out (~20 minutes) waiting for `ACTIVE`.

## Usage

Prefer the [`compute/eks`](../..) composite. This module is nested under
`compute/eks/modules/` and is not independently published.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster to install add-ons on. | `string` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| coredns_addon_version | Pinned version for the coredns add-on. When null, AWS resolves the most recent compatible version. | `string` | `null` | no |
| coredns_addon_configuration_values | JSON string of add-on configuration overrides for coredns. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| coredns_addon_arn | ARN of the coredns EKS add-on. |
| coredns_addon_version | Resolved version of the coredns EKS add-on. |
