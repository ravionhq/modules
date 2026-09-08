# EKS Hosting (composite)

Root-style stack that nests EKS primitives under `modules/` and composes them
into a single hosting unit with enforced provisioning order:

1. **Cluster** (`modules/eks_cluster`) — control plane, OIDC, secrets KMS,
   vpc-cni / kube-proxy / Pod Identity Agent, LB Controller role
2. **Default capacity node group** (`system_node_group`, using
   `modules/eks_node_group`) — required compute for cluster components, add-ons,
   and workloads without stricter placement
3. **Post-compute add-ons** (`modules/eks_addons`) — CoreDNS
   (deadlock without step 2)
4. **Optional Fargate** (`modules/eks_fargate_profile`) — after add-ons are
    healthy
5. **Dedicated access relay** — private ARM AL2023 EC2, EKS-only SSM Port
   document, read-only access role and deploy/admin Runner access

This stack talks only to the AWS API, so it provisions in a single apply with
no connectivity to the cluster's Kubernetes endpoint. Optional extensions —
Karpenter autoscaling, the AWS Load Balancer Controller, the External Secrets
Operator, the EBS CSI driver, and Container Insights — live in
the separate [`compute/eks/addons`](addons/) stack as selectable add-ons, so
clusters only carry what they use.

Child modules live in `compute/eks/modules/` and are **not** independently
published root stacks — they have no `provider` / `cloud {}` blocks. Callers
should consume this composite only.

## Usage

```hcl
module "eks" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks?ref=main"

  name   = "platform"
  region = "us-east-1"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version             = "1.31"
  endpoint_public_access_enabled = true

  tags = { Environment = "prod" }
}
```

> **Pinning a `ref`:** this repository has no `vX.Y.Z` tags. Releases are tagged
> per module definition as `rvn-<definition-type>@<x.y.z>` (for example
> `rvn-aws-network@1.0.1`). Once a release of this stack is cut, pin to
> `?ref=rvn-eks-cluster@<x.y.z>`; until then use `?ref=main` or a commit SHA.

## Requirements

The connection relay requires private EKS endpoint access and a private subnet
with NAT or existing SSM interface endpoints (`ssm`, `ssmmessages`, and where
needed `ec2messages`) and private DNS. Endpoint security groups must allow relay
HTTPS. No NAT or endpoint resources are created here. The subnet check rejects
public-IP subnets and declared public subnet IDs; callers must also verify route
tables. The VPC's DNS support/resolver must be enabled.

## SSM access contract

Every cluster receives a dedicated `t4g.micro` (optionally `t4g.nano`) relay,
separate from Kubernetes nodes. It has an ARM64 AL2023 AMI, encrypted 8 GiB gp3
root disk, IMDSv2 with hop limit 1, no public IP/key pair/inbound rules, and SSH
disabled. Its instance role grants **only AmazonSSMManagedInstanceCore**.
HTTPS egress reaches EKS and SSM; `ravion_access_ssm_egress_cidrs` can restrict SSM
destinations to private endpoint CIDRs. VPC DNS traffic uses the AWS resolver.

`ravion_access_session_document_name` is a per-cluster Session document with
`sessionType=Port`. It pins the remote host to this cluster's EKS hostname and
the remote port to 443. The only caller parameter is `localPortNumber`, default
`0` (plugin-selected). Do not send `host` or `portNumber` parameters. TLS clients
must use the original EKS hostname for SNI/verification and the cluster CA while
connecting through the localhost tunnel; never disable certificate validation.

Discover exactly one running EC2 instance by both:

- `RavionPurpose=eks-access-relay`
- `RavionClusterArn=<full EKS cluster ARN>`

The EC2 instance also carries `RavionSessionDocument`, `RavionAccessRoleArn`, and
`RavionReadRoleArn`. Module contract tags take precedence over user tags.
`RavionAccessRoleArn` is empty if admin role creation is disabled; consumers must
reject admin operations rather than falling back to another identity.

The read role has AmazonEKSViewPolicy and group `ravion:readers`. Add-ons grants
that group narrowly scoped GET service proxy access to managed Loki/Prometheus.
Add-ons also bootstraps read-only node, live-metrics, storage and Karpenter
inventory access omitted by AWS View. Full node inventory requires that bootstrap.
Observers receive namespace-scoped get/list Secrets through the add-ons bootstrap
for Helm inventory/drift, in the union of configured workload and observed
namespaces. This permits reading **all Secret contents** in those namespaces;
Kubernetes RBAC cannot limit list permission by Helm labels. No ClusterRole grants
Secrets access, and observers cannot exec or pod-forward. The deploy/admin role is the
existing Runner role with AmazonEKSClusterAdminPolicy and scoped SSM access;
authorized interactive operations use this role. The control plane must authorize
the user before selecting it. Configure trusted principals separately for reads
and deployments; empty lists trust this account and still require caller-side
`sts:AssumeRole`. Cross-account role ARNs are supported. Runner trust preserves
role-path ARN patterns with an explicit account ID.

Both EKS access-role trust policies permit `sts:AssumeRole` and
`sts:SetSourceIdentity` for the same trusted principals. This preserves the
broker's OIDC source identity during role chaining; callers must have the matching
permissions. The EC2 relay's service trust remains independent.

Both roles can start sessions only on this relay with the dedicated document.
Opening the data channel is permitted for session ARNs in this account/region
and requires the bearer token returned by the scoped StartSession/ResumeSession.
Resume/terminate use SSM system tags to require the caller's `aws:userid` and
this relay target (assumed-role session ARNs do not contain the full userid).
Use unique assumed-role session names for distinct ownership. Additional IAM
policies are additive: do not attach broad session permissions to these roles.

A single relay is not highly available. AMI updates/replacement interrupt active
connections; runtime consumers should rediscover and reconnect. Mocked tests do
not prove live SSM registration, effective IAM or network connectivity. Follow
the [staged Operator migration guide](addons/UPGRADE-SSM.md) for existing clusters.

## Provider requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 6.0    |
| tls                | >= 4.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | EKS cluster name. | `string` | n/a | yes |
| vpc_id | VPC ID for the control plane. | `string` | n/a | yes |
| subnet_ids | Control plane subnets (>=2); default node/Fargate placement. | `list(string)` | n/a | yes |
| node_subnet_ids | Optional node/Fargate subnet override. | `list(string)` | `null` | no |
| region | AWS region for the root provider. | `string` | `null` | no |
| tags | Tags applied to all created resources. | `map(string)` | `{}` | no |
| kubernetes_version | Cluster Kubernetes version (`MAJOR.MINOR`). | `string` | `null` | no |
| endpoint_public_access_enabled | Expose the API server publicly. | `bool` | `false` | no |
| endpoint_private_access_enabled | Expose the API server inside the VPC. | `bool` | `true` | no |
| public_access_cidrs | CIDRs allowed to hit the public endpoint. | `list(string)` | `["0.0.0.0/0"]` | no |
| service_ipv4_cidr | Override the service CIDR. | `string` | `null` | no |
| ip_family | `ipv4` or `ipv6`. | `string` | `"ipv4"` | no |
| cluster_security_group_additional_cidr_ingress_rules | Extra cluster-SG ingress sourced by IPv4 CIDR. | `list(object)` | `[]` | no |
| cluster_security_group_additional_referenced_security_group_ingress_rules | Extra cluster-SG ingress sourced by another security group. | `list(object)` | `[]` | no |
| bootstrap_cluster_creator_admin_permissions_enabled | Auto-grant cluster-admin to the creating principal during cluster bootstrap. | `bool` | `true` | no |
| access_entries | EKS access entries. | `map(object)` | `{}` | no |
| enabled_cluster_log_types | Control plane log types. | `list(string)` | `["api","audit","authenticator"]` | no |
| cluster_log_retention_in_days | Control plane log retention. | `number` | `30` | no |
| secrets_encryption_enabled | Envelope-encrypt Kubernetes secrets. | `bool` | `true` | no |
| secrets_kms_key_arn | Existing secrets KMS key ARN. | `string` | `null` | no |
| vpc_cni_addon_version / kube_proxy_addon_version | Pinned DaemonSet add-on versions. | `string` | `null` | no |
| vpc_cni_addon_configuration_values / kube_proxy_addon_configuration_values | JSON config overrides. | `string` | `null` | no |
| pod_identity_agent_enabled | Install eks-pod-identity-agent. | `bool` | `true` | no |
| pod_identity_agent_addon_version | Pin pod identity agent version. | `string` | `null` | no |
| aws_load_balancer_controller_pod_identity_creation_enabled | Create the AWS Load Balancer Controller Pod Identity role and association. | `bool` | `true` | no |
| aws_load_balancer_controller_namespace / aws_load_balancer_controller_service_account | AWS Load Balancer Controller service account location. | `string` | `"kube-system"` / `"aws-load-balancer-controller"` | no |
| ravion_runner_security_group_creation_enabled | Create a Ravion Runner SG allowed to reach the API endpoint (443). | `bool` | `true` | no |
| ravion_runner_role_creation_enabled | Create an assumable IAM role registered as an EKS access entry with cluster-admin, for runner Kubernetes API access. | `bool` | `true` | no |
| ravion_runner_role_trusted_principal_arns | ArnLike patterns restricting who can assume the Ravion Runner role (empty = same-account principals with sts:AssumeRole). | `list(string)` | `[]` | no |
| pod_identity_associations | Extra Pod Identity associations. | `map(object)` | `{}` | no |
| deletion_protection_enabled | Protect the cluster from API deletion. | `bool` | `true` | no |
| system_node_group | Default managed node group config. The minimum size is also its initial size; group disk settings remain independent of the relay. | `object` | `{}` (defaults: name=`system`, 2-4 ON_DEMAND t3.medium) | no |
| node_groups | Extra node groups keyed by name. Each group's minimum size is also its initial size. | `map(object)` | `{}` | no |
| coredns_addon_version / coredns_addon_configuration_values | CoreDNS pin / JSON overrides. | `string` | `null` | no |
| fargate_profiles | Fargate profiles keyed by name (`selectors` required). | `map(object)` | `{}` | no |
| ravion_access_relay_instance_type | Dedicated ARM relay size (`t4g.micro` or `t4g.nano`). | `string` | `"t4g.micro"` | no |
| ravion_access_relay_subnet_id | Private subnet; falls back to the first cluster subnet. | `string` | `null` | no |
| ravion_access_ssm_egress_cidrs | IPv4 HTTPS egress destinations for SSM. | `list(string)` | `["0.0.0.0/0"]` | no |
| ravion_access_read_trusted_principal_arns | Trusted IAM read principals, including cross-account roles. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name / cluster_arn | Cluster identifiers. |
| cluster_endpoint | Kubernetes API server URL. |
| cluster_certificate_authority_data | Base64 CA cert for kubeconfig. |
| cluster_version | Kubernetes version. |
| region / aws_account_id | Deployment location. |
| oidc_issuer_url / oidc_provider_arn | IRSA wiring. |
| cluster_security_group_id | EKS-managed cluster security group. |
| node_subnet_ids | Subnets used for node placement (consumed by `addons`). |
| ravion_runner_security_group_id | Ravion Runner SG allowed to reach the API endpoint (null if disabled). |
| ravion_runner_role_arn | IAM role runners assume for Kubernetes API access (null if disabled). |
| ravion_access_relay_instance_id | Dedicated EC2 SSM target, never a Kubernetes node. |
| ravion_access_session_document_name | Per-cluster EKS-only SSM Port document. |
| ravion_access_role_arn | Deploy/admin role alias of `ravion_runner_role_arn` (null if disabled). |
| ravion_access_read_role_arn | Separate read-only EKS and scoped SSM role. |
| secrets_kms_key_arn | Secrets KMS key (null if disabled). |
| lb_controller_role_arn | LB Controller Pod Identity role. |
| system_node_group_name / system_node_group_arn | System node group identifiers. |
| additional_node_group_names | Map of additional node group key -> name. |
| fargate_profile_names | Map of Fargate profile key -> name. |

## Notes

- Ordering is intentional: CoreDNS is a Deployment and hangs `DEGRADED` for
  ~20 minutes when no compute exists. The composite `depends_on` chain
  prevents that deadlock.
- This module creates no optional add-ons. Karpenter autoscaling, the External
  Secrets Operator, the EBS CSI driver, and Container Insights are selectable
  toggles on the [`compute/eks/addons`](addons/) stack, deployed against this
  cluster.
- `secrets_encryption_enabled` (default `true`) puts Kubernetes Secrets in etcd
  under KMS envelope encryption, using a dedicated CMK per cluster unless
  `secrets_kms_key_arn` supplies one. That is the at-rest half of the secrets
  story; the reference half — workloads naming Secrets Manager / Parameter
  Store ARNs instead of carrying values — is the External Secrets Operator
  add-on, documented in [`compute/eks/addons`](addons/#secrets-external-secrets-operator).
- Nested modules under `modules/` are internal implementation details of this
  composite — do not instantiate them as separate root stacks.
