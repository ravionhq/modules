# rvn-gke-worker

Ravion application chart for a long-running background workload on GKE, ported from
`rvn-eks-worker`. Deployed by the `rvn-gke-worker` module definition
(`compute/gke_service`).

## Differences from rvn-eks-worker

| Concern | rvn-eks-worker | rvn-gke-worker |
| --- | --- | --- |
| Workload identity | EKS Pod Identity association by ServiceAccount name | `serviceAccount.gcpServiceAccount` → `iam.gke.io/gcp-service-account` annotation naming the stack's Google service account |
| Secrets | `ravion.secrets[].provider` picks the Secrets Manager or Parameter Store store; `key` is an ARN | One Secret Manager store (`ravion.secretStores.secretManager`, default `ravion-gcp`); `key` is a secret ID or `projects/<p>/secrets/<id>` |
| Spot burst placement | `eks.amazonaws.com/capacityType` / `karpenter.sh/capacity-type` | `cloud.google.com/gke-spot`; the Spot pool tolerates the GKE Spot taint |

All other values match `rvn-eks-worker`; see `values.yaml` and `values.schema.json`.
The schema is the public API: values are added, never removed or repurposed,
within a major version.
