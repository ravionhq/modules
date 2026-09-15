# rvn-eks-worker

Ravion application chart for a long-running background worker on EKS.

Renders a Deployment, a Pod Identity ServiceAccount, optionally a
HorizontalPodAutoscaler, and optionally an ExternalSecret. There is deliberately
**no Service, no Ingress, no TargetGroupBinding, no container port, and no
probe** — a worker has no inbound network surface.

The image / env / resources / secrets surface is identical to
[`rvn-eks-web`](../rvn-eks-web), so an app can move between the two shapes
without rewriting those values.

Chart version `0.1.0`. See [compatibility policy](../README.md#values-schema-is-a-public-api).

## Usage

```yaml
source:
  type: inline
  repo: https://github.com/ravionhq/modules
  branch: main
  ref: rvn-eks@0.1.0
  chart: charts/rvn-eks-worker
```

```yaml
image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
  tag: v1.2.3
args: ["worker", "--queue=default"]
env:
  - name: QUEUE
    value: default
```

## Deploy config → values mapping

| Deploy config | Chart value | Notes |
|---------------|-------------|-------|
| Image | `image.repository` + `image.tag`, or `image.digest` | A digest wins over a tag. |
| Start command | `command` / `args` | |
| CPU / memory | `resources.requests`, `resources.limits` | |
| Environment variables | `env` — `[{name, value}]` | |
| Secrets | `ravion.secrets` — references only | See [the secrets contract](../README.md#the-secrets-contract). |
| Instance count | `replicaCount`, or `autoscaling.*` | `replicaCount` is omitted from the Deployment when the HPA is enabled. |
| IAM role | `serviceAccount.name` | The name the Pod Identity association targets. |

## Values

### Image and command

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `image.repository` | string | `""` | Image repository. **Required.** |
| `image.tag` | string | `""` | Required unless `image.digest` is set. |
| `image.digest` | string | `""` | `sha256:…` digest. Takes precedence over `tag`. |
| `image.pullPolicy` | string | `IfNotPresent` | |
| `imagePullSecrets` | list | `[]` | |
| `command` | list(string) | `[]` | Overrides the image ENTRYPOINT. |
| `args` | list(string) | `[]` | Overrides the image CMD. |
| `env` | list | `[]` | `[{name, value}]`. Non-secret variables only. |

### Scale and scheduling

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `replicaCount` | int | `1` | Ignored when `autoscaling.enabled`. |
| `autoscaling.enabled` | bool | `false` | |
| `autoscaling.minReplicas` | int | `1` | |
| `autoscaling.maxReplicas` | int | `10` | |
| `autoscaling.targetCPUUtilizationPercentage` | int/null | `70` | |
| `autoscaling.targetMemoryUtilizationPercentage` | int/null | `null` | |
| `strategy.type` | string | `RollingUpdate` | Or `Recreate`. |
| `strategy.maxSurge` | string/int | `25%` | |
| `strategy.maxUnavailable` | string/int | `0` | |
| `revisionHistoryLimit` | int | `10` | |
| `terminationGracePeriodSeconds` | int | `30` | Time to drain in-flight work before SIGKILL. |
| `resources.requests` | map | `{cpu: 100m, memory: 256Mi}` | |
| `resources.limits` | map | `{memory: 512Mi}` | |
| `nodeSelector` | map | `{}` | |
| `tolerations` | list | `[]` | |
| `affinity` | map | `{}` | |
| `topologySpread.enabled` | bool | `true` | Render one zone spread constraint on this chart's pods so workers run in every zone. |
| `topologySpread.maxSkew` | int | `1` | |
| `topologySpread.whenUnsatisfiable` | string | `ScheduleAnyway` | Or `DoNotSchedule` for a hard requirement. |
| `topologySpreadConstraints` | list | `[]` | Explicit constraints. When non-empty, replaces the default zone spread. |

### Identity, metadata, storage

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `serviceAccount.create` | bool | `true` | |
| `serviceAccount.name` | string | `""` | Defaults to the release fullname. The name the Pod Identity association targets; no IRSA annotation is emitted. |
| `serviceAccount.annotations` | map | `{}` | |
| `serviceAccount.automountServiceAccountToken` | bool | `true` | |
| `nameOverride` / `fullnameOverride` | string | `""` | |
| `commonLabels` | map | `{}` | |
| `annotations` | map | `{}` | On the Deployment object. |
| `podAnnotations` / `podLabels` | map | `{}` | |
| `podSecurityContext` / `securityContext` | map | `{}` | |
| `volumes` / `volumeMounts` | list | `[]` | |

### Secrets

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `ravion.secrets` | list | `[]` | References only: `[{name, provider, key, property?, version?}]`. |
| `ravion.secretStores.kind` | string | `ClusterSecretStore` | |
| `ravion.secretStores.secretsManager` | string | `ravion-aws` | |
| `ravion.secretStores.parameterStore` | string | `ravion-aws-parameter-store` | |
| `ravion.secretRefreshInterval` | string | `1h` | |

Full contract: [the charts README](../README.md#the-secrets-contract).

## Not in 0.1.0

Workers get no probes. A liveness probe for a worker is necessarily
`exec`-shaped rather than HTTP-shaped, which is a different values shape from
`rvn-eks-web`'s; adding it later is a compatible MINOR change behind a
default-off toggle.
