"""Render the pinned mimir-distributed chart with the module's placement values.

mimir.tftest.hcl pins what the module writes; this checks the chart turns it
into pods that cannot share a node: the anti-affinity selector must match the
labels the chart puts on its pods, and the store placement's node affinity must
survive Helm merging the value files. It also checks the store-gateways' Go
memory limit from the resilience values replaces the one the chart derives from
their memory request. Requires Helm, yq v4 and network
access to the Grafana chart repository.

Run: python3 -B -m unittest discover -s compute/eks/addons/tests -p 'test_mimir_chart_placement.py'
"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ADDONS = Path(__file__).resolve().parents[1]
RELEASE = "ravion-mimir"

# What mimir.tf writes for each replicated component outside zone-aware mode.
COMPONENTS = {"ingester": "ingester", "store_gateway": "store-gateway"}


def chart_version():
    variables = (ADDONS / "variables.tf").read_text()
    block = re.search(r'variable "mimir_chart_version" \{.*?\n\}', variables, re.S).group(0)
    return re.search(r'default\s*=\s*"([^"]+)"', block).group(1)


def anti_affinity(label):
    return {"podAntiAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": [{
        "topologyKey": "kubernetes.io/hostname",
        "labelSelector": {"matchLabels": {
            "app.kubernetes.io/component": label,
            "app.kubernetes.io/instance": RELEASE,
            "app.kubernetes.io/name": "mimir",
        }},
    }]}}


# What the resilience values write for the store-gateways: 90% of the 3Gi limit.
STORE_GATEWAY_RESILIENCE = {
    "resources": {"requests": {"cpu": "500m", "memory": "2Gi"}, "limits": {"memory": "3Gi"}},
    "env": [{"name": "GOMEMLIMIT", "value": "2764MiB"}],
}


NODE_AFFINITY = {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": {
    "nodeSelectorTerms": [{"matchExpressions": [
        {"key": "karpenter.sh/nodepool", "operator": "In", "values": ["addon-stateful"]},
    ]}],
}}}


class MimirChartPlacementTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            # The module's first values document, then the store placement on top.
            base = Path(directory) / "base.json"
            base.write_text(json.dumps({
                "fullnameOverride": RELEASE,
                "minio": {"enabled": False},
                "kafka": {"enabled": False},
                "mimir": {"structuredConfig": {"ingest_storage": {"enabled": False}}},
                **{component: {"zoneAwareReplication": {"enabled": False}, "affinity": anti_affinity(label)}
                   for component, label in COMPONENTS.items()},
            }))
            placement = Path(directory) / "placement.json"
            placement.write_text(json.dumps({component: {"affinity": NODE_AFFINITY} for component in COMPONENTS}))
            resilience = Path(directory) / "resilience.json"
            resilience.write_text(json.dumps({"store_gateway": STORE_GATEWAY_RESILIENCE}))
            # Helm's own config and cache, so repositories added on the machine
            # running the test cannot get in the way.
            env = {**os.environ, **{name: str(Path(directory) / name) for name in ("HELM_CONFIG_HOME", "HELM_CACHE_HOME", "HELM_DATA_HOME")}}
            rendered = subprocess.run([
                "helm", "template", RELEASE, "mimir-distributed",
                "--repo", "https://grafana.github.io/helm-charts", "--version", chart_version(),
                "--namespace", "ravion-operator", "--values", str(base), "--values", str(placement), "--values", str(resilience),
                # Helm's default is older than the chart's kubeVersion floor.
                "--kube-version", "1.36.0",
            ], text=True, capture_output=True, timeout=180, env=env)
        if rendered.returncode != 0:
            raise AssertionError(rendered.stderr)
        parsed = subprocess.run(
            ["yq", "ea", "-o=json", "-I=0", '[select(.kind == "StatefulSet")]', "-"],
            input=rendered.stdout, text=True, capture_output=True, timeout=30,
        )
        if parsed.returncode != 0:
            raise AssertionError(parsed.stderr)
        cls.statefulsets = {s["metadata"]["labels"]["app.kubernetes.io/component"]: s for s in json.loads(parsed.stdout)}

    def test_anti_affinity_selects_the_pods_the_chart_creates(self):
        for label in COMPONENTS.values():
            with self.subTest(component=label):
                pod = self.statefulsets[label]["spec"]["template"]
                terms = pod["spec"]["affinity"]["podAntiAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"]
                self.assertEqual(len(terms), 1)
                selector = terms[0]["labelSelector"]["matchLabels"]
                self.assertLessEqual(selector.items(), pod["metadata"]["labels"].items(),
                                     "the selector must match the chart's own pod labels")
                self.assertEqual(terms[0]["topologyKey"], "kubernetes.io/hostname")

    def test_anti_affinity_selects_only_its_own_component(self):
        for label in COMPONENTS.values():
            with self.subTest(component=label):
                selector = self.statefulsets[label]["spec"]["template"]["spec"]["affinity"]["podAntiAffinity"][
                    "requiredDuringSchedulingIgnoredDuringExecution"][0]["labelSelector"]["matchLabels"]
                for other, statefulset in self.statefulsets.items():
                    if other != label:
                        self.assertFalse(selector.items() <= statefulset["spec"]["template"]["metadata"]["labels"].items(),
                                         f"{label}'s selector must not match {other} pods")

    def test_node_affinity_survives_the_merge(self):
        for label in COMPONENTS.values():
            with self.subTest(component=label):
                affinity = self.statefulsets[label]["spec"]["template"]["spec"]["affinity"]
                self.assertEqual(affinity["nodeAffinity"], NODE_AFFINITY["nodeAffinity"])

    def test_store_gateway_go_memory_limit_replaces_the_chart_default(self):
        container = next(c for c in self.statefulsets["store-gateway"]["spec"]["template"]["spec"]["containers"]
                         if c["name"] == "store-gateway")
        limits = [e for e in container["env"] if e["name"] == "GOMEMLIMIT"]
        self.assertEqual(limits, [{"name": "GOMEMLIMIT", "value": "2764MiB"}],
                         "the module's GOMEMLIMIT must replace the chart's request-sized one, not sit beside it")


if __name__ == "__main__":
    unittest.main()
