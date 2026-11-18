# rvn-gke-cron

Ravion application chart for a scheduled job on GKE, ported from
`rvn-eks-cron`. Deployed by the `rvn-gke-cron` module definition
(`compute/gke_service`).

## Differences from rvn-eks-cron

| Concern | rvn-eks-cron | rvn-gke-cron |
| --- | --- | --- |
| Workload identity | EKS Pod Identity association by ServiceAccount name | `serviceAccount.gcpServiceAccount` → `iam.gke.io/gcp-service-account` annotation naming the stack's Google service account |
| Secrets | `ravion.secrets[].provider` picks the Secrets Manager or Parameter Store store; `key` is an ARN | One Secret Manager store (`ravion.secretStores.secretManager`, default `ravion-gcp`); `key` is a secret ID or `projects/<p>/secrets/<id>` |

All other values match `rvn-eks-cron`; see `values.yaml` and `values.schema.json`.
The schema is the public API: values are added, never removed or repurposed,
within a major version.
