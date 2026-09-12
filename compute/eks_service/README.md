# EKS Service Infrastructure

The AWS-side infrastructure for a single EKS workload: an optional ECR repository, an optional workload-specific EKS Fargate profile, plus an optional Application Load Balancer attachment made of one IP-mode `aws_lb_target_group` and one `aws_lb_listener_rule` on a shared listener created by [`compute/eks/addons`](../eks/addons).

Each part is independently optional, which is what lets one root module serve all three EKS workload definitions. Selecting Fargate adds a profile and pod execution role to any row below; omitting `fargate_profile` leaves scheduling to existing cluster compute:

| Caller | `ecr_repository_creation_enabled` | `listener_arn` | Creates |
|--------|-----------------------------------|----------------|---------|
| `rvn-eks-web`, Dockerfile or Railpack build | `true` | set | ECR repository, target group, listener rule |
| `rvn-eks-web`, registry image | `false` | set | Target group, listener rule |
| `rvn-eks-worker`, `rvn-eks-cron`, Dockerfile or Railpack build | `true` | `null` | ECR repository |
| `rvn-eks-worker`, `rvn-eks-cron`, registry image | `false` | `null` | Nothing |

This mirrors `compute/ecs_service`, where one root module serves web, worker, and NLB services, gating ECR on `ecr_repository_creation_enabled` and the load balancer on a nullable `load_balancer_attachment`.

The workload itself is not created here. Pods are deployed by Helm (the `rvn-eks-web`, `rvn-eks-worker`, and `rvn-eks-cron` charts), and the AWS Load Balancer Controller registers the Service's pod IPs into the target group through a `TargetGroupBinding` that the web chart renders from the `target_group_arn` output. Terraform owns the AWS objects; Helm owns the workload. This is the same split `compute/ecs_service` uses, with ECS's `RegisterTargets` replaced by the controller.

## Usage

A web workload with a built image, a load balancer attachment, and an ECR repository:

```hcl
module "web" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks_service?ref=rvn-eks-web@0.2.0"

  name   = "acme-prod-api"
  region = "us-east-1"
  vpc_id = "vpc-0a1b2c3d4e5f67890"

  ecr_repository_creation_enabled = true

  listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/acme-pub/50dc.../f2f7..."
  container_port = 8080

  listener_rule_conditions = [
    {
      type   = "host-header"
      values = ["api.example.com"]
    }
  ]

  target_group_health_check = {
    path    = "/healthz"
    matcher = "200-399"
  }

  # Destroying the stack uninstalls the Helm release Ravion deployed for this
  # workload, before the target group and repository are removed.
  workload_release_cleanup_enabled = true
  cluster_name                     = "acme-prod"
  ravion_runner_role_arn           = "arn:aws:iam::123456789012:role/acme-prod-ravion-runner"
  release_name                     = "acme-prod-api"
  release_namespace                = "acme-prod"

  # Optional: create a dedicated on-demand Fargate profile for this workload.
  fargate_profile = {
    name       = "acme-prod-api-fargate"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    selectors = [{
      namespace = "acme-prod"
      labels = {
        "app.kubernetes.io/instance" = "acme-prod-api"
      }
    }]
  }

  tags = {
    Owner = "Ravion"
  }
}
```

A worker or cron workload, which needs the image repository but no load balancer:

```hcl
module "worker" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks_service?ref=rvn-eks-worker@0.2.0"

  name   = "acme-prod-worker"
  region = "us-east-1"
  vpc_id = "vpc-0a1b2c3d4e5f67890"

  ecr_repository_creation_enabled = true

  # No listener: no target group, no listener rule, and every load balancer
  # output is null.
  listener_arn = null
}
```

## Workload release teardown

Ravion installs the workload's Helm release from the deploy path, not from
Terraform, but destroying this stack removes it all the same. With
`workload_release_cleanup_enabled`, a `terraform_data` resource carries a
destroy-time provisioner that runs `helm uninstall <release_name> -n
<release_namespace> --wait` against the cluster, authenticated with `aws eks
get-token --role-arn <ravion_runner_role_arn>`. It depends on the target group,
listener rule and repository, so Terraform runs it first and the workload drains
while those still exist.

- A cluster that no longer exists is treated as "nothing to uninstall" (the
  cluster stack may be destroyed first); a release that is already gone is a
  no-op. A cluster that exists but cannot be reached, or an uninstall that
  fails, fails the destroy before anything else is removed.
- The identity is captured in state at apply time, so the release removed is
  the one installed, and re-pointing `release_name`/`release_namespace`
  replaces the resource, which uninstalls the old release.
- `helm` is downloaded (checksum-verified) when none is on PATH; `aws` is
  required. The namespace itself is never deleted.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name for the target group, listener rule, ECR repository, and related resources | `string` | n/a | yes |
| vpc_id | ID of the VPC the EKS cluster runs in; the target group must live in the same VPC as the pods | `string` | n/a | yes |
| listener_arn | ARN of the shared load balancer listener the rule is attached to; `null` disables the load balancer attachment entirely | `string` | `null` | no |
| region | AWS region; when null the provider's configured region is used | `string` | `null` | no |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |
| ecr_repository_creation_enabled | Create an ECR repository for this workload's container image | `bool` | `false` | no |
| ecr_repository_name | Name of the ECR repository; falls back to `name` | `string` | `null` | no |
| ecr_image_tag_mutability | Tag mutability, `MUTABLE` or `IMMUTABLE` | `string` | `"MUTABLE"` | no |
| ecr_image_scan_on_push_enabled | Scan images for vulnerabilities on push | `bool` | `true` | no |
| ecr_force_delete_enabled | Allow deleting the repository while it still holds images | `bool` | `false` | no |
| ecr_default_lifecycle_policy_enabled | Apply the `containers/ecr` built-in lifecycle policy | `bool` | `false` | no |
| fargate_profile | Workload-specific EKS Fargate profile with `name`, private `subnet_ids`, and one or more namespace/label `selectors`; `null` disables it | `object` | `null` | no |
| workload_release_cleanup_enabled | Uninstall the workload's Helm release when the stack is destroyed | `bool` | `false` | no |
| cluster_name | EKS cluster the workload runs on; required with `workload_release_cleanup_enabled` or `fargate_profile` | `string` | `null` | no |
| ravion_runner_role_arn | The cluster's `<cluster>-ravion-runner` role, assumed via `aws eks get-token` for the uninstall | `string` | `null` | no |
| release_name | Helm release name Ravion installs for this workload | `string` | `null` | no |
| release_namespace | Namespace the release is installed into (never removed itself) | `string` | `null` | no |
| workload_release_helm_version | Helm downloaded for the uninstall when none is on PATH | `string` | `"v4.2.4"` | no |
| workload_release_uninstall_timeout | `helm uninstall --wait` timeout | `string` | `"10m"` | no |
| container_port | Port the application container listens on | `number` | `8080` | no |
| target_group_protocol | Protocol the load balancer uses to reach pods (`HTTP` or `HTTPS`) | `string` | `"HTTP"` | no |
| target_group_deregistration_delay | Seconds before a target is deregistered, letting in-flight requests drain | `number` | `300` | no |
| target_group_slow_start | Seconds over which traffic ramps to a newly registered target; `0` disables | `number` | `0` | no |
| target_group_health_check | Load balancer health check settings for the target group | `object` | see below | no |
| target_group_stickiness | Target group cookie stickiness settings | `object` | see below | no |
| listener_rule_priority | Listener rule priority; when null AWS assigns the next available one | `number` | `null` | no |
| listener_rule_conditions | Conditions that route requests to this service | `list(object)` | catch-all `/*` | no |

Every variable from `container_port` down is load-balancer-only and ignored when `listener_arn` is `null`. All of them have defaults, so a worker or cron caller can omit the whole block.

### `target_group_health_check`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | `bool` | `true` | Whether the target group performs health checks |
| path | `string` | `"/"` | HTTP path requested |
| port | `string` | `"traffic-port"` | Port checked; `traffic-port` uses the target group port |
| protocol | `string` | `null` | Falls back to `target_group_protocol` |
| matcher | `string` | `"200-399"` | Status codes treated as healthy |
| interval | `number` | `15` | Seconds between checks |
| timeout | `number` | `5` | Seconds to wait for a response; must be lower than `interval` |
| healthy_threshold | `number` | `2` | Consecutive successes before a target is healthy |
| unhealthy_threshold | `number` | `2` | Consecutive failures before a target is unhealthy |

This health check is independent of the chart's Kubernetes readiness probe. The probe decides whether kubelet considers the pod ready; this one decides whether the load balancer sends it traffic.

### `target_group_stickiness`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | `bool` | `false` | Enable cookie stickiness |
| type | `string` | `"lb_cookie"` | `lb_cookie` or `app_cookie` |
| cookie_duration | `number` | `86400` | Seconds the stickiness cookie lives |
| cookie_name | `string` | `null` | Required when `type` is `app_cookie` |

### `listener_rule_conditions`

Each entry is `{ type, values }`. Supported types: `host-header`, `path-pattern`, `http-header`, `http-request-method`, `query-string`, `source-ip`. A rule AND-combines all of its conditions. For `http-header`, the first value is the header name and the rest are matched values. For `query-string`, the first value is the key and the second the value.

## Outputs

| Name | Description |
|------|-------------|
| target_group_arn | ARN of the target group, passed to the chart as `targetGroupArns` |
| target_group_arn_suffix | ARN suffix of the target group, for CloudWatch metrics |
| target_group_name | Name of the target group |
| listener_rule_arn | ARN of the listener rule |
| listener_rule_priority | Priority assigned to the listener rule |
| load_balancer_arn | ARN of the shared load balancer the listener belongs to |
| load_balancer_dns_name | DNS name of the shared load balancer |
| load_balancer_zone_id | Route 53 hosted zone ID of the load balancer, for alias records |
| load_balancer_arn_suffix | ARN suffix of the load balancer, for CloudWatch metrics |
| ecr_repository_arn | ARN of the ECR repository, the build's push destination |
| ecr_repository_name | Name of the ECR repository |
| ecr_repository_url | URL of the ECR repository, passed to the chart as `image.repository` |
| fargate_profile_name | Name of the workload's EKS Fargate profile |
| fargate_profile_arn | ARN of the workload's EKS Fargate profile |
| vpc_id | ID of the VPC the target group was created in |
| region | AWS region where the resources are deployed |

Every load balancer output is `null` when `listener_arn` is `null`, every `ecr_*` output is `null` when `ecr_repository_creation_enabled` is `false`, and both `fargate_profile_*` outputs are `null` when `fargate_profile` is `null`. Consumers can read them unconditionally.

## Design decisions

- **One root module for all three workloads.** Web, worker, and cron each need an ECR repository when Ravion builds their image, any of them may need a Fargate profile, and only web needs a load balancer. Gating all three resource groups here keeps one stack per workload while matching `compute/ecs_service`'s optional ECR and load-balancer pattern.
- **Fargate profiles are workload-specific.** A profile can select one release by namespace and its standard `app.kubernetes.io/instance` label. Fargate uses on-demand capacity and private subnets only; callers that omit the object create no profile or pod execution role.
- **The ECR repository is created, not referenced.** The build needs a push destination that exists before the first build, and a per-module repository keeps image lifecycle and access scoped to one workload. Callers deploying a pre-built image set `ecr_repository_creation_enabled = false` and the module creates no repository.
- **One target group, no alternate.** `compute/ecs_service` creates a `tg-1`/`tg-2` pair plus a test listener rule so ECS's native controller can shift traffic between them. The 2026-08-06 load balancer ADR on ENG-5033 scopes EKS v1 to rolling Deployment updates, so there is no alternate target group, no test rule, and no traffic-shift configuration here.
- **No `ignore_changes` on the listener rule action.** The ECS module has to ignore `action` because the ECS deployment controller rewrites it mid-deploy. Nothing outside Terraform touches this rule, so drift here is real drift and should be corrected.
- **`target_type` is fixed to `ip`.** The AWS Load Balancer Controller registers pod IPs; `instance` mode would require a `NodePort` Service, which the chart does not render.
- **Listener rules only, no NLB listeners.** NLB-fronted EKS workloads are outside this module.
