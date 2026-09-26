# Ravion Operator namespaces

Internal Helm chart used by the EKS Add-ons Terraform module before installing
Operator's namespaced RBAC. `namespaces` is the deduplicated union of observation
and enabled deployment scopes.

- Missing namespaces are created.
- Existing namespaces belonging to this release remain in its manifest on upgrade.
- Existing namespaces managed elsewhere are not adopted or modified.
- Every namespace created here has `helm.sh/resource-policy: keep`, so removing it
  from the list or uninstalling the release retains it and its workloads. Deletion
  is an explicit administrative operation.

The release lives in `kube-system` so moving the agent does not move namespace
ownership. Lookups run against Kubernetes during apply; an offline `helm template`
cannot detect existing namespaces. The Terraform runner needs namespace read and
create permissions; no extra permissions are granted to the Operator.

From `compute/eks/addons`, run the chart lookup tests using Python 3 and Helm:

```sh
python3 -B -m unittest discover -s tests -p 'test_namespace_chart.py'
```

The tests use a local read-only Kubernetes API stub and never use your cluster
context. They cover missing, externally managed, other-release-owned, and
same-release-owned namespaces. They do not perform a real Helm uninstall.
