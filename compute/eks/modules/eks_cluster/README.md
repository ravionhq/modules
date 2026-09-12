# EKS Cluster

Internal child module of [`compute/eks`](../..) — consumed via the composite only; not independently versioned or published.

Provisions an Amazon EKS cluster control plane with the pieces every cluster
actually needs:

- The cluster itself, with `authentication_mode = API` (no aws-auth ConfigMap).
- An IAM service role for the control plane.
- An optional OIDC identity provider for IRSA-based workloads (default off).
- Optional KMS envelope encryption for Kubernetes secrets (default on).
- Optional CloudWatch control-plane logging with a managed log group (default on).
- Core add-ons: `vpc-cni`, `kube-proxy`.
- Optional add-on: `eks-pod-identity-agent` (default on).
- A Pod Identity role + association for the AWS Load Balancer Controller (consumer Helm-installs the controller).
- Caller-driven access entries (`var.access_entries`) and pod identity associations (`var.pod_identity_associations`).

> **Breaking change (v2.0.0):** Deployment-kind add-ons (`coredns`,
> `aws-ebs-csi-driver` + its Pod Identity role) moved to
> `compute/eks/modules/eks_addons`, which the composite applies **after**
> the system node group exists.
> Keeping them in the cluster module caused create-time deadlocks on clusters
> with no node groups (add-ons hang `DEGRADED` for ~20 minutes then fail).

Node groups, Fargate profiles, Karpenter, and post-compute add-ons are sibling
modules under `compute/eks/modules/` (`eks_node_group`, `eks_fargate_profile`,
`eks_karpenter`, `eks_addons`), orchestrated by the composite.

## Usage

Prefer the [`compute/eks`](../..) composite. This module is nested under
`compute/eks/modules/` and is not independently published.

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| opentofu/terraform | >= 1.10.0  |
| aws                | >= 6.0     |
| tls                | >= 4.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the EKS cluster. | `string` | n/a | yes |
| kubernetes_version | Kubernetes version (`MAJOR.MINOR`). | `string` | `null` | no |
| vpc_id | VPC ID to launch the control plane ENIs into. | `string` | n/a | yes |
| subnet_ids | Subnets for control plane ENIs (>=2, multi-AZ). | `list(string)` | n/a | yes |
| endpoint_public_access_enabled | Expose the API server publicly. | `bool` | `false` | no |
| endpoint_private_access_enabled | Expose the API server inside the VPC. | `bool` | `true` | no |
| public_access_cidrs | CIDRs allowed to hit the public endpoint. | `list(string)` | `["0.0.0.0/0"]` | no |
| service_ipv4_cidr | Override the service CIDR (IPv4 only). | `string` | `null` | no |
| ip_family | `ipv4` or `ipv6`. | `string` | `"ipv4"` | no |
| cluster_security_group_additional_cidr_ingress_rules | Extra cluster-SG ingress rules sourced by IPv4 CIDR. | `list(object)` | `[]` | no |
| cluster_security_group_additional_referenced_security_group_ingress_rules | Extra cluster-SG ingress rules sourced by another security group. | `list(object)` | `[]` | no |
| bootstrap_cluster_creator_admin_permissions_enabled | Auto-grant cluster-admin to the creating principal during cluster bootstrap. | `bool` | `true` | no |
| access_entries | EKS access entries to create (replaces aws-auth ConfigMap). | `map(object)` | `{}` | no |
| oidc_provider_creation_enabled | Create an IAM OIDC provider for IRSA workloads. | `bool` | `false` | no |
| vpc_resource_controller_policy_enabled | Attach AmazonEKSVPCResourceController for Windows networking or security groups for pods. | `bool` | `false` | no |
| enabled_cluster_log_types | Control plane log types to ship to CloudWatch. | `list(string)` | `["api","audit","authenticator"]` | no |
| cluster_log_retention_in_days | Retention for the control plane log group. | `number` | `30` | no |
| secrets_encryption_enabled | Envelope-encrypt Kubernetes secrets with KMS. | `bool` | `true` | no |
| secrets_kms_key_arn | Existing KMS key ARN; null = create one. | `string` | `null` | no |
| vpc_cni_addon_version / kube_proxy_addon_version | Pinned add-on versions. | `string` | `null` | no |
| vpc_cni_addon_configuration_values / kube_proxy_addon_configuration_values | JSON config overrides. | `string` | `null` | no |
| pod_identity_agent_enabled | Install eks-pod-identity-agent. | `bool` | `true` | no |
| pod_identity_agent_addon_version | Pin pod identity agent add-on version. | `string` | `null` | no |
| aws_load_balancer_controller_pod_identity_creation_enabled | Create the AWS Load Balancer Controller Pod Identity role and association. | `bool` | `true` | no |
| aws_load_balancer_controller_namespace | Namespace of the AWS Load Balancer Controller service account. | `string` | `"kube-system"` | no |
| aws_load_balancer_controller_service_account | Name of the AWS Load Balancer Controller service account. | `string` | `"aws-load-balancer-controller"` | no |
| pod_identity_associations | Extra `{ namespace, service_account, role_arn }` associations. | `map(object)` | `{}` | no |
| tags | Tags applied to all created resources. | `map(string)` | `{}` | no |
| deletion_protection_enabled | If true, the resource cannot be deleted via the AWS API until this is set to false. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id / cluster_arn / cluster_name | Cluster identifiers. |
| cluster_endpoint | Kubernetes API server URL. |
| cluster_certificate_authority_data | Base64 CA cert for kubeconfig. |
| cluster_version / cluster_platform_version / cluster_status | Cluster state. |
| cluster_security_group_id / cluster_vpc_config | Networking outputs. |
| cluster_iam_role_arn / cluster_iam_role_name | Control plane service role. |
| oidc_issuer_url / oidc_issuer_host / oidc_provider_arn | IRSA wiring; provider ARN is null unless creation is enabled. |
| secrets_kms_key_arn | Secrets KMS key (null if disabled). |
| cloudwatch_log_group_name / cloudwatch_log_group_arn | Control plane log group. |
| lb_controller_role_arn / lb_controller_role_name | LB Controller Pod Identity role. |
| aws_account_id / region | Account & region info. |

## Notes

- The OIDC provider and TLS lookup run only with `oidc_provider_creation_enabled=true`. Pod Identity needs neither. Existing IRSA installations must opt in before upgrading; a moved block retains their provider without replacement. Otherwise an existing provider is removed.
- The cluster role always includes `AmazonEKSClusterPolicy`. `AmazonEKSVPCResourceController` is opt-in via `vpc_resource_controller_policy_enabled`; enable it before upgrading clusters using Windows networking or security groups for pods. Otherwise the previously default attachment is removed.
- The LB Controller's IAM policy is vendored from `kubernetes-sigs/aws-load-balancer-controller` upstream (`docs/install/iam_policy.json`) at `policies/lb_controller.json`. Refresh that file when you upgrade the controller version.
- Pod Identity needs the `eks-pod-identity-agent` add-on. Disabling it (`pod_identity_agent_enabled = false`) without disabling the helper roles will leave their associations created but non-functional at runtime.
- For CoreDNS and the EBS CSI driver, the composite applies `modules/eks_addons` after the system node group exists.
