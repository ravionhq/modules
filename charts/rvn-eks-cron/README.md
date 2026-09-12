# rvn-eks-cron

Ravion application chart for a scheduled job on EKS.

Renders a CronJob, a Pod Identity ServiceAccount, and optionally an
ExternalSecret. No Service, no Deployment, no load-balancer surface.

The pod spec mirrors [`rvn-eks-worker`](../rvn-eks-worker) — same image / env /
resources / secrets values — so a worker can become a cron and back without
rewriting them. `schedule` is the only required value beyond the image.

Chart version `0.1.0`. See [compatibility policy](../README.md#values-schema-is-a-public-api).

## Usage

```yaml
source:
  type: inline
  repo: https://github.com/ravionhq/modules
  branch: main
  ref: rvn-eks@0.1.0
  chart: charts/rvn-eks-cron
```

```yaml
image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
  tag: v1.2.3
schedule: "0 3 * * *"
args: ["rake", "db:cleanup"]
```

## Deploy config → values mapping

| Deploy config | Chart value | Notes |
|---------------|-------------|-------|
| Image | `image.repository` + `image.tag`, or `image.digest` | A digest wins over a tag. |
| Schedule | `schedule` | Cron expression. **Required.** |
| Time zone | `timeZone` | IANA name. Empty means the controller's zone, usually UTC. |
| Command | `command` / `args` | |
| CPU / memory | `resources.requests`, `resources.limits` | |
| Environment variables | `env` — `[{name, value}]` | |
| Secrets | `ravion.secrets` — references only | See [the secrets contract](../README.md#the-secrets-contract). |
| IAM role | `serviceAccount.name` | The name the Pod Identity association targets. |

## Values

### Schedule

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `schedule` | string | `""` | Cron expression, e.g. `0 3 * * *`. **Required.** |
| `timeZone` | string | `""` | IANA time zone. Omitted from the manifest when empty. |
| `concurrencyPolicy` | string | `Allow` | `Allow`, `Forbid`, or `Replace` when the previous run is still going. |
| `suspend` | bool | `false` | Stop scheduling new runs without deleting the CronJob. |
| `successfulJobsHistoryLimit` | int | `3` | |
| `failedJobsHistoryLimit` | int | `1` | |
| `startingDeadlineSeconds` | int/null | `null` | Seconds after a missed schedule in which a run may still start. Omitted when null. |

### Job

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `job.backoffLimit` | int | `3` | Retries before the run is marked failed. |
| `job.activeDeadlineSeconds` | int/null | `null` | Wall-clock limit for a run. Omitted when null. |
| `job.ttlSecondsAfterFinished` | int/null | `null` | How long a finished Job object is retained. Omitted when null. |
| `job.restartPolicy` | string | `OnFailure` | Or `Never`. |

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
| `resources.requests` | map | `{cpu: 100m, memory: 256Mi}` | |
| `resources.limits` | map | `{memory: 512Mi}` | |
| `terminationGracePeriodSeconds` | int | `30` | |

### Identity, metadata, scheduling, storage

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `serviceAccount.create` | bool | `true` | |
| `serviceAccount.name` | string | `""` | Defaults to the release fullname. The name the Pod Identity association targets; no IRSA annotation is emitted. |
| `serviceAccount.annotations` | map | `{}` | |
| `serviceAccount.automountServiceAccountToken` | bool | `true` | |
| `nameOverride` / `fullnameOverride` | string | `""` | |
| `commonLabels` | map | `{}` | |
| `annotations` | map | `{}` | On the CronJob object. |
| `podAnnotations` / `podLabels` | map | `{}` | |
| `podSecurityContext` / `securityContext` | map | `{}` | |
| `nodeSelector` | map | `{}` | |
| `tolerations` | list | `[]` | |
| `affinity` | map | `{}` | |
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
