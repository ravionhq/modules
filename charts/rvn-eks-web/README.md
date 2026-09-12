# rvn-eks-web

Ravion application chart for a long-running HTTP workload on EKS.

Renders a Deployment, a ClusterIP Service, a Pod Identity ServiceAccount,
optionally a HorizontalPodAutoscaler, optionally one TargetGroupBinding per
supplied target group ARN, and optionally an ExternalSecret. **It never renders
an Ingress** — see [the charts README](../README.md#load-balancing-rvn-eks-web).

Chart version `0.1.0`. See [compatibility policy](../README.md#values-schema-is-a-public-api).

## Usage

Deployed by the Ravion runner from an inline chart source:

```yaml
source:
  type: inline
  repo: https://github.com/ravionhq/modules
  branch: main
  ref: rvn-eks@0.1.0
  chart: charts/rvn-eks-web
```

Minimal values — a container, a port, and a health check:

```yaml
image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
  tag: v1.2.3
containerPort: 3000
probes:
  liveness:
    path: /healthz
  readiness:
    path: /healthz
```

Locally:

```bash
helm template my-app charts/rvn-eks-web --values charts/rvn-eks-web/ci/full-values.yaml
```

## Deploy config → values mapping

| Deploy config | Chart value | Notes |
|---------------|-------------|-------|
| Image | `image.repository` + `image.tag`, or `image.digest` | A digest wins over a tag. One of the two is required. |
| Port | `containerPort` | Rendered as the container port named `http`; the Service and all probes default to it. |
| Health check path | `probes.liveness.path`, `probes.readiness.path` | Both default to `/`. |
| Health check timings | `probes.*.initialDelaySeconds`, `.periodSeconds`, `.timeoutSeconds`, `.failureThreshold` | |
| CPU / memory | `resources.requests`, `resources.limits` | Passed through verbatim as Kubernetes quantities. |
| Environment variables | `env` — `[{name, value}]` | Values are always quoted, so numeric-looking values stay strings. |
| Secrets | `ravion.secrets` — references only | See [the secrets contract](../README.md#the-secrets-contract). |
| Instance count | `replicaCount`, or `autoscaling.*` | `replicaCount` is omitted from the Deployment when the HPA is enabled, so the HPA owns scale. |
| Load balancer attachment | `targetGroupArns` | ARNs of Terraform-owned target groups. |
| IAM role | `serviceAccount.name` | The name the Pod Identity association targets. |

## Values

### Image and command

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `image.repository` | string | `""` | Image repository. **Required.** |
| `image.tag` | string | `""` | Image tag. Required unless `image.digest` is set. |
| `image.digest` | string | `""` | `sha256:…` digest. Takes precedence over `tag`. |
| `image.pullPolicy` | string | `IfNotPresent` | `Always`, `IfNotPresent`, or `Never`. |
| `imagePullSecrets` | list | `[]` | e.g. `[{name: ecr-creds}]`. |
| `command` | list(string) | `[]` | Overrides the image ENTRYPOINT. |
| `args` | list(string) | `[]` | Overrides the image CMD. |
| `env` | list | `[]` | `[{name, value}]`. Non-secret variables only. |

### Networking

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `containerPort` | int | `8080` | Port the app listens on; exposed as the port named `http`. |
| `service.port` | int | `80` | Port the Service exposes. The TargetGroupBinding references it. |
| `service.targetPort` | string/int | `""` | Container port name or number. Defaults to `http`. |
| `service.type` | string | `ClusterIP` | |
| `service.annotations` | map | `{}` | |
| `service.appProtocol` | string | `""` | e.g. `http`, `grpc`. |
| `service.trafficDistribution` | string | `PreferClose` | Route in-cluster callers to same-zone pods when any exist, else any zone. Needs Kubernetes 1.31+. Set `""` to spread evenly across zones. |
| `targetGroupArns` | list(string) | `[]` | Terraform-owned target group ARNs. One TargetGroupBinding per entry; none render when empty. |
| `targetGroupBinding.targetType` | string | `ip` | Must match the target group's `target_type`. |
| `targetGroupBinding.vpcId` | string | `""` | Only needed for a cross-VPC target group. |

### Health checks

Each of `probes.liveness`, `probes.readiness`, `probes.startup` takes the same
shape. Liveness and readiness are on by default; startup is off.

| Value | Type | Default (liveness / readiness / startup) | Description |
|-------|------|------------------------------------------|-------------|
| `probes.<p>.enabled` | bool | `true` / `true` / `false` | |
| `probes.<p>.path` | string | `/` / `/` / `""` | Startup falls back to the readiness path. |
| `probes.<p>.port` | string/int | `""` | Defaults to the `http` port. |
| `probes.<p>.initialDelaySeconds` | int | `10` / `5` / `0` | |
| `probes.<p>.periodSeconds` | int | `10` / `10` / `5` | |
| `probes.<p>.timeoutSeconds` | int | `5` | |
| `probes.<p>.failureThreshold` | int | `3` / `3` / `30` | |
| `probes.readiness.successThreshold` | int | `1` | Readiness only. |

### Scale and scheduling

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `replicaCount` | int | `1` | Ignored when `autoscaling.enabled`. |
| `autoscaling.enabled` | bool | `false` | |
| `autoscaling.minReplicas` | int | `1` | |
| `autoscaling.maxReplicas` | int | `10` | |
| `autoscaling.targetCPUUtilizationPercentage` | int/null | `70` | Set `null` to drop the CPU metric. |
| `autoscaling.targetMemoryUtilizationPercentage` | int/null | `null` | Set a number to add a memory metric. |
| `strategy.type` | string | `RollingUpdate` | Or `Recreate`. |
| `strategy.maxSurge` | string/int | `25%` | |
| `strategy.maxUnavailable` | string/int | `0` | Zero-downtime by default. |
| `revisionHistoryLimit` | int | `10` | |
| `terminationGracePeriodSeconds` | int | `30` | |
| `resources.requests` | map | `{cpu: 100m, memory: 256Mi}` | |
| `resources.limits` | map | `{memory: 512Mi}` | No CPU limit by default, to avoid throttling. |
| `nodeSelector` | map | `{}` | |
| `tolerations` | list | `[]` | |
| `affinity` | map | `{}` | |
| `topologySpread.enabled` | bool | `true` | Render one zone spread constraint on this chart's pods so each zone has a local endpoint. |
| `topologySpread.maxSkew` | int | `1` | |
| `topologySpread.whenUnsatisfiable` | string | `ScheduleAnyway` | Or `DoNotSchedule` for a hard requirement. |
| `topologySpreadConstraints` | list | `[]` | Explicit constraints. When non-empty, replaces the default zone spread. |

### Identity, metadata, storage

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `serviceAccount.create` | bool | `true` | |
| `serviceAccount.name` | string | `""` | Defaults to the release fullname. This is the name the Pod Identity association targets. No IRSA annotation is emitted. |
| `serviceAccount.annotations` | map | `{}` | |
| `serviceAccount.automountServiceAccountToken` | bool | `true` | |
| `nameOverride` / `fullnameOverride` | string | `""` | |
| `commonLabels` | map | `{}` | Applied to every object; never to the immutable selector. |
| `annotations` | map | `{}` | On the Deployment object. |
| `podAnnotations` / `podLabels` | map | `{}` | |
| `podSecurityContext` / `securityContext` | map | `{}` | Pod- and container-level. |
| `volumes` / `volumeMounts` | list | `[]` | |

### Secrets

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `ravion.secrets` | list | `[]` | References only: `[{name, provider, key, property?, version?}]`. |
| `ravion.secretStores.kind` | string | `ClusterSecretStore` | Or `SecretStore`. |
| `ravion.secretStores.secretsManager` | string | `ravion-aws` | Store for `secretsManager` entries. |
| `ravion.secretStores.parameterStore` | string | `ravion-aws-parameter-store` | Store for `parameterStore` entries. |
| `ravion.secretRefreshInterval` | string | `1h` | How often ESO re-reads the remote values. |

Full contract: [the charts README](../README.md#the-secrets-contract).
