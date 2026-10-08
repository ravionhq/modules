# rvn-eks-worker

Ravion application chart for a long-running background worker on EKS.

Renders a Deployment, a Pod Identity ServiceAccount, optionally a
HorizontalPodAutoscaler, and optionally an ExternalSecret. There is deliberately
**no Service, no Ingress, no TargetGroupBinding, no container port, and no
probe** — a worker has no inbound network surface.

The image / env / resources / secrets surface is identical to
[`rvn-eks-web`](../rvn-eks-web), so an app can move between the two shapes
without rewriting those values.

Chart version `0.4.0`. See [compatibility policy](../README.md#values-schema-is-a-public-api).

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
| `strategy.maxSurge` | string/int | `100%` | Full replacement set; lower to limit temporary capacity. |
| `strategy.maxUnavailable` | string/int | `0` | |
| `podDisruptionBudget.enabled` | bool | `true` | Render a `policy/v1` PodDisruptionBudget (with `unhealthyPodEvictionPolicy: AlwaysAllow`) limiting voluntary disruptions such as node drains and autoscaler consolidation. A worker loses its in-flight work when it is evicted, so a fleet drained at once loses all of it. Skipped when the replica floor (`autoscaling.minReplicas`, or `replicaCount`) is not greater than `minAvailable`, because such a budget allows no evictions and blocks every drain. |
| `podDisruptionBudget.minAvailable` | int | `1` | Pods that must stay available during a voluntary disruption. |
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

### KEDA Spot burst

`spotBurst.enabled` keeps the baseline Deployment on On-Demand capacity and adds a separate Spot-only Deployment controlled by a KEDA `ScaledObject`. The fixed baseline uses `spotBurst.baselineReplicas`; the Spot pool starts at zero and scales from zero to `spotBurst.maxReplicas`. The ordinary CPU/memory HPA is not rendered while burst mode is enabled. On first creation, the Spot Deployment renders with zero replicas, including when enabling the feature on an existing release. Zero replicas do not exercise the new Spot image; verify activation and readiness separately in staging. Subsequent Helm upgrades preserve the live Spot Deployment replica count through Kubernetes `lookup`; offline renders therefore show zero, and the deployment identity needs permission to read Deployments in the release namespace. Verify lookup access and scale transitions in staging. Turning burst mode off removes its Deployment and `ScaledObject` and restores the ordinary single-pool scaling behavior.

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `spotBurst.enabled` | bool | `false` | Enable the optional second pool; requires KEDA in the EKS add-ons module. |
| `spotBurst.kedaEnabled` | bool | `false` | KEDA prerequisite reported by the selected add-ons module. |
| `spotBurst.baselineReplicas` | int | `2` | Fixed On-Demand replica floor; minimum `1`. |
| `spotBurst.maxReplicas` | int | `8` | Maximum KEDA-managed Spot replicas; minimum `1`. |
| `spotBurst.pollingInterval` | int | `30` | KEDA polling interval in seconds; minimum `1`. |
| `spotBurst.cooldownPeriod` | int | `300` | KEDA cooldown in seconds; minimum `0`. |
| `spotBurst.triggers` | list | `[]` | Required when enabled. At least one trigger must work when the Spot Deployment has zero replicas; CPU or memory alone cannot wake it. |

Choose a zero-independent signal, such as external queue depth, and set thresholds with the fixed baseline's capacity in mind so already-served baseline work does not cause unnecessary Spot scaling. Configure any trigger authentication separately: referenced `TriggerAuthentication`, `ClusterTriggerAuthentication`, and Kubernetes Secrets must already exist. Do not put credential values in trigger metadata; the add-ons module grants no metric-source permissions.

The EKS add-ons module installs KEDA 2.20.2 by default when selected. Its published Kubernetes test matrix covers 1.33–1.35; verify newer versions, including 1.36, in staging. Spot availability is not guaranteed and each active pod incurs compute cost. The Spot pool reuses the same image and pod configuration; review duplicate job processing and idempotency, and do not expect the feature to migrate application code or configuration automatically.

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
