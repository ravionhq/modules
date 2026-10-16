# Ravion Thanos

Internal chart installed by `compute/eks/addons/thanos.tf`. It connects to the Thanos sidecar injected into the existing Prometheus chart; it does not install another scraper or remote-write receiver.

- **Query**: ClusterIP HTTP API on port 9090; merges the sidecar's recent data and Store Gateway's S3 history.
- **Store Gateway**: read-only S3 access, with a disposable 10Gi index cache.
- **Compactor**: singleton StatefulSet with a 20Gi working PVC; owns compaction, downsampling and retention at every resolution. Never run another compactor against this bucket.

`objstoreConfig` contains a bucket, regional endpoint and SDK credential-chain settings, not secrets. The parent module creates separate EKS Pod Identity roles for sidecar, store and compactor. Query has no S3 grant. Services are private and unauthenticated; no Ingress or load balancer is created.

## Values

| Value | Default | Purpose |
|---|---|---|
| `image` | `quay.io/thanos/thanos:v0.42.4` | Shared Thanos image |
| `objstoreConfig` | required | Non-secret S3 configuration |
| `prometheusRelease` | `ravion-prometheus` | Release whose server pods carry the sidecar |
| `retentionDays` | `365` | Compactor retention at raw, 5m and 1h resolutions |
| `query.resources`, `store.resources`, `compactor.resources` | 100m CPU / 256Mi memory requests; 1Gi memory limit | Pod sizing |
| `compactor.storageSize` | `20Gi` | Persistent compaction working space; size for the largest compaction group |
| `compactor.storageClass` | cluster default | Parent uses managed encrypted `gp3` when available |
| `nodeSelector`, `tolerations` | empty | Pod placement |
| `query.replicas`, `store.replicas` | `1` | Above one, replicas prefer distinct nodes and each component gets a `minAvailable: 1` PodDisruptionBudget. The parent module sets 2 with `addon_resilience_enabled` |
| `priorityClassName` | empty | Applied to every component; the parent module sets `system-cluster-critical` |
| `compactor.podAnnotations` | empty | Compactor pod annotations; the parent module sets `karpenter.sh/do-not-disrupt` |
| `compactor.affinity`, `compactor.tolerations` | empty (the top-level values) | Compactor placement, apart from Query and Store; the parent module pins it to the stateful add-on NodePool |
| `replicaLabel` | empty | External label telling Prometheus replicas apart; when set, Query merges their copies of each series (`--query.replica-label`). The parent module sets `prometheus_replica` with more than one Prometheus replica |

Query reaches the Prometheus sidecars and the Store Gateways through headless Services (`<release>-sidecar-headless`, `<release>-store-headless`), so it holds a connection to every replica rather than one per ClusterIP.

Tune these through `thanos_helm_values`. Retained StatefulSet PVCs are not deleted on chart uninstall. S3 history lifecycle is controlled separately by the parent Terraform module.

## Tests

From the repository root, after initializing add-ons with `tofu init -backend=false` and installing `tools/ravion-modules` dependencies:

```sh
node --test compute/eks/addons/tests/test_s3_observability_charts.mjs
RAVION_OBSERVABILITY_VALIDATE_IMAGES=1 node --test compute/eks/addons/tests/test_s3_observability_charts.mjs
```

The suite renders pinned charts with actual mock-plan Helm values. The optional image checks require Docker and validate the generated Tempo and trace collector configurations without network access. These are not live AWS ingestion tests.
