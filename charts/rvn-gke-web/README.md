# rvn-gke-web

Ravion application chart for a long-running HTTP workload on GKE, ported from
`rvn-eks-web`. Deployed by the `rvn-gke-web` module definition
(`compute/gke_service`).

Renders a Deployment, a ClusterIP Service, a ServiceAccount, and optionally a
HorizontalPodAutoscaler, a PodDisruptionBudget, a NetworkPolicy allow-list, a
KEDA-scaled Spot Deployment, an ExternalSecret, and a GKE Gateway.

## Differences from rvn-eks-web

| Concern | rvn-eks-web | rvn-gke-web |
| --- | --- | --- |
| Load balancer | `targetGroupArns` → TargetGroupBinding on a Terraform-owned target group | `gateway.*` → Gateway, HTTPRoute, HealthCheckPolicy and GCPBackendPolicy; GKE programs an Application Load Balancer |
| Load balancer readiness | ELB readiness gate per binding | NEG readiness gate GKE injects into Gateway backends |
| Workload identity | EKS Pod Identity association by ServiceAccount name | `serviceAccount.gcpServiceAccount` → `iam.gke.io/gcp-service-account` annotation naming the stack's Google service account |
| Secrets | `ravion.secrets[].provider` picks the Secrets Manager or Parameter Store store; `key` is an ARN | One Secret Manager store (`ravion.secretStores.secretManager`, default `ravion-gcp`); `key` is a secret ID or `projects/<p>/secrets/<id>` |
| Spot burst placement | `eks.amazonaws.com/capacityType` / `karpenter.sh/capacity-type` | `cloud.google.com/gke-spot`; the Spot pool tolerates the GKE Spot taint |

## Gateway values

| Value | Default | Description |
| --- | --- | --- |
| `gateway.enabled` | `false` | Render the Gateway and its route and policies |
| `gateway.className` | `gke-l7-global-external-managed` | Or `gke-l7-rilb` for a regional internal load balancer |
| `gateway.addressName` | `""` | Reserved address the Gateway uses (`spec.addresses` NamedAddress) |
| `gateway.hostnames` | `[]` | HTTPRoute hostnames; empty matches every host |
| `gateway.pathPrefixes` | `[]` | HTTPRoute path prefixes; empty matches `/` |
| `gateway.certificateMapName` | `""` | Certificate Manager map (external only); adds an HTTPS listener |
| `gateway.preSharedCertificateNames` | `[]` | Compute Engine SSL certificates; adds an HTTPS listener |
| `gateway.httpsRedirect` | `true` | Redirect HTTP to HTTPS when HTTPS is configured |
| `gateway.healthCheck.*` | `/`, 5s, 4s, 2, 2 | Load balancer health check |
| `gateway.drainingTimeoutSeconds` | `300` | Connection draining for removed pods |
| `gateway.sessionAffinity.type` | `""` | `CLIENT_IP` or `GENERATED_COOKIE` |

All other values match `rvn-eks-web`; see `values.yaml` and `values.schema.json`.
The schema is the public API: values are added, never removed or repurposed,
within a major version.
