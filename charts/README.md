# Ravion application charts

Versioned, Ravion-maintained Helm charts for **chart-less apps** — users who
bring a container image and no chart of their own. "Chart generation" in Ravion
is values synthesis onto these charts, not per-user chart codegen.

| Chart | Workload shape | Kubernetes objects |
|-------|----------------|--------------------|
| [`rvn-eks-web`](rvn-eks-web) | Long-running HTTP service behind a shared load balancer | Deployment, Service, ServiceAccount, optional HPA, optional TargetGroupBinding, optional ExternalSecret |
| [`rvn-eks-worker`](rvn-eks-worker) | Long-running background process | Deployment, ServiceAccount, optional HPA, optional ExternalSecret |
| [`rvn-eks-cron`](rvn-eks-cron) | Scheduled job | CronJob, ServiceAccount, optional ExternalSecret |

## Why these live at the repository root

The Ravion deploy runner consumes these charts by **cloning this repository and
resolving a repo-relative path**, not by pulling from a chart registry. The
module deploy block names a `git` chart source:

```yaml
source:
  type: git
  repo_url: https://github.com/ravionhq/modules
  branch: main
  ref: rvn-eks@0.1.0             # exact tag or SHA — this is what pins the version
  base_path: charts/rvn-eks-web  # resolved against the clone root
```

The runner stats `<clone-root>/<base_path>/Chart.yaml` and runs
`helm upgrade --install <release> <that directory>`. Any depth would work
mechanically, so placement is a readability decision, and `charts/` at the root
is the one that matches what these charts are:

- **They are deployed per app by the runner, not installed by Terraform.**
  `compute/eks/addons/charts/karpenter-resources` sits under the addons module
  because that module installs it, via `${path.module}/charts/karpenter-resources`
  in `karpenter.tf`. Nothing in `compute/eks/addons` installs these charts, so
  filing them there would imply a lifecycle they do not have.
- **They version independently of any Terraform module.** They are released
  under their own `rvn-eks@<version>` tags and pinned per deployment by `ref`.
  Nesting them inside a module directory would tangle their versioning with
  that module's.
- **They are not category-scoped.** `<category>/<module-name>/` in `AGENTS.md`
  describes Terraform modules. These are not Terraform modules and have none of
  the required module files (`variables.tf`, `outputs.tf`, `versions.tf`).

`charts/rvn-eks-web` is also the path already written into the monorepo's
deploy-schema documentation and test fixtures
(`packages/schemas/modules/tsp/deployment.tsp`).

The karpenter chart remains the precedent for **structure** — a plain
`Chart.yaml` + `values.yaml` + `templates/` application chart with no
dependencies — which these follow.

## Values schema is a public API

Each chart ships a `values.schema.json` that Helm enforces on every
`lint`/`template`/`install`. The schema uses `additionalProperties: false`, so a
typo in a values key is a hard error rather than a silently ignored setting.

**Compatibility policy**, matching the repo's semantic-versioning guidelines:

| Change | Version bump | Allowed within a major version |
|--------|--------------|-------------------------------|
| New optional value with a default that preserves current rendering | MINOR | yes |
| New rendered object behind a default-off toggle | MINOR | yes |
| Default value changed in a way that changes rendered output | MAJOR | no |
| Value removed, renamed, or repurposed | MAJOR | no |
| Rendered output changed for unchanged values | MAJOR | no |
| Template comment, README, or schema description fix | PATCH | yes |

Because each deployment pins an exact `ref`, an in-place chart fix plus a
version bump upgrades every consumer on their next deploy — that central
patchability is the reason for versioned charts over per-deploy generation.

## The secrets contract

Ravion never sends secret values. It writes secret **references** under the
reserved `ravion` values key, which user-authored values may not declare (the
tower-side resolver rejects a user `ravion` key):

```yaml
ravion:
  secrets:
    - name: DB_PASSWORD          # env var name inside the container
      provider: secretsManager   # or parameterStore
      key: arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf
      property: password         # optional: JSON key within the secret payload
      version: AWSCURRENT        # optional
```

Each chart renders that into one `ExternalSecret` (`external-secrets.io/v1`)
targeting a chart-managed Kubernetes Secret, plus one
`env[].valueFrom.secretKeyRef` per entry. When `ravion.secrets` is empty, no
`ExternalSecret` and no `Secret` render at all.

`secretKeyRef` is used rather than `envFrom` deliberately: it fails the pod
closed if a key has not materialized, instead of starting the container with the
variable silently unset.

### SecretStores

ESO's AWS provider takes **one service per store**, so the ESO addon in
`compute/eks/addons` provisions two `ClusterSecretStore`s and exposes their
names as Terraform outputs:

| Provider | Store name (default) | Value |
|----------|----------------------|-------|
| `secretsManager` | `ravion-aws` | `ravion.secretStores.secretsManager` |
| `parameterStore` | `ravion-aws-parameter-store` | `ravion.secretStores.parameterStore` |

A single `ExternalSecret` carries one top-level `secretStoreRef`, so the charts
pick the store the majority of entries need as the default and override the
remainder per entry with `sourceRef.storeRef`. A workload using only Parameter
Store therefore never names the Secrets Manager store, and a mixed workload
still gets one `ExternalSecret` and one target Secret.

Neither name is hardcoded — both are values, defaulted to the addon's
conventional names.

### What is never in a chart

No secret value appears in values, in a template, in the rendered manifest, or
in the Helm release object stored in etcd. In particular the charts never take a
value that would end up in a `Secret`'s `data`/`stringData`; the only Secret
involved is the one ESO writes.

## Load balancing (rvn-eks-web)

`rvn-eks-web` **does not emit an Ingress**. The controller-owned Ingress→ALB
path was rejected in favour of ECS parity: the workload module's Terraform owns
the `aws_lb_target_group` and `aws_lb_listener_rule` against the shared load
balancer from `compute/eks/addons`, mirroring `rvn-ecs-web`'s
`target_groups.tf` / `listener_rules.tf`. The chart's only contribution is a
`TargetGroupBinding`, which tells the AWS Load Balancer Controller to register
the Service's pod IPs into that target group.

The controller is installed by `compute/eks/addons` whenever any shared load
balancer is enabled, so the CRD can be assumed present exactly when
`targetGroupArns` is non-empty. Nothing renders when it is empty.

## Pod Identity

None of the charts emit an IRSA `eks.amazonaws.com/role-arn` annotation. EKS Pod
Identity associates an IAM role with a service account by **namespace + name**
from the AWS side, so the charts' only obligation is a stable, configurable
`serviceAccount.name` for the `aws_eks_pod_identity_association` to target. It
defaults to the release fullname.

## Testing

```bash
make test-charts                   # all three charts
make test-charts CHART=rvn-eks-web # one chart
./charts/test.sh                   # same thing, directly
```

`charts/test.sh` needs `helm` and `yq` and **no cluster**: it runs `helm lint`
for every chart against every `ci/*-values.yaml`, then asserts against
`helm template` output. It runs in CI via `.github/workflows/helm-charts.yml`.

The `ci/*-values.yaml` files are both lint fixtures and worked examples.
