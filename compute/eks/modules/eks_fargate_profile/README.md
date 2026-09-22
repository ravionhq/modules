# EKS Fargate Profile

Internal child module of [`compute/eks`](../..) — consumed via the composite only; not independently versioned or published.

Provisions one EKS Fargate profile and (optionally) the pod execution role
required by Fargate's infrastructure to pull images and write logs.

Instantiate this module once per profile. EKS evaluates pods against profile
selectors in lexicographic order and the first match wins, so design
namespaces / labels deliberately if you have multiple profiles.

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
| cluster_name | Name of the EKS cluster. | `string` | n/a | yes |
| name | Name of the Fargate profile. | `string` | n/a | yes |
| subnet_ids | Private subnets for Fargate pods. | `list(string)` | n/a | yes |
| selectors | List of `{ namespace, labels }`. | `list(object)` | n/a | yes |
| pod_execution_role_arn | BYO pod execution role. When null, module creates one. | `string` | `null` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| partition | AWS partition used to build managed policy ARNs. Pass from the caller when instantiating with `depends_on` so ARNs are known at plan time; resolved via data source when null. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| fargate_profile_arn / fargate_profile_id / fargate_profile_name | Profile identifiers. |
| fargate_profile_status | EKS-reported status. |
| pod_execution_role_arn / pod_execution_role_name | Pod execution role. |
| aws_account_id / region | Account & region info. |

## Notes

- Fargate cannot run in public subnets — the pod ENIs need an outbound NAT path. Pass private subnets only.
- Fargate pods cannot use IRSA via STS web identity for their pod execution role; that role is the *infrastructure* role, distinct from the IAM role your application code receives via IRSA / Pod Identity. Wire your app's IAM identity separately.
