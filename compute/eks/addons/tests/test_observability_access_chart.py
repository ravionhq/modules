"""Render read-proxy RBAC locally; never contacts Kubernetes."""

import json
from pathlib import Path
import re
import subprocess
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts/observability-access"


class ObservabilityAccessChartTest(unittest.TestCase):
    def render(self, values):
        return subprocess.run(
            ["helm", "template", "ravion-observability-access", str(CHART), "-f", "-"],
            input=json.dumps(values), text=True, capture_output=True, check=True,
        ).stdout

    def test_each_service_is_bound_only_in_its_namespace(self):
        result = self.render({
            "namespaces": ["logs", "metrics"],
            "services": [
                {"namespace": "logs", "name": "ravion-loki", "port": "3100"},
                {"namespace": "metrics", "name": "ravion-prometheus-server", "port": "9090"},
            ],
        })
        roles = [doc for doc in result.split("---") if re.search(r"^kind: Role$", doc, re.MULTILINE)]
        self.assertEqual(len(roles), 2)
        for role in roles:
            self.assertIn('resources: ["services/proxy"]', role)
            self.assertIn('verbs: ["get"]', role)
            self.assertIn("resourceNames:", role)
            if 'namespace: "logs"' in role:
                self.assertIn('"http:ravion-loki:3100"', role)
                self.assertNotIn("prometheus", role)
            else:
                self.assertIn('namespace: "metrics"', role)
                self.assertIn('"http:ravion-prometheus-server:9090"', role)
                self.assertNotIn("loki", role)
        self.assertEqual(result.count("kind: RoleBinding"), 2)
        self.assertEqual(result.count("name: ravion:readers"), 2)
        for forbidden in ["ClusterRole", '"*"', "pods/exec", "pods/portforward", "secrets", '"create"']:
            self.assertNotIn(forbidden, result)

    def test_no_permissions_without_destinations(self):
        self.assertEqual(self.render({"namespaces": [], "services": []}).strip(), "")

    def test_inventory_reads_never_grant_interactive_or_secret_access(self):
        result = self.render({"clusterInventoryEnabled": True, "namespaces": [], "services": []})
        self.assertIn("kind: ClusterRole\n", result)
        self.assertIn("kind: ClusterRoleBinding\n", result)
        self.assertIn('resources: ["nodes", "persistentvolumes"]', result)
        self.assertIn('apiGroups: ["metrics.k8s.io"]', result)
        self.assertIn("name: ravion:readers", result)
        for forbidden in ['"*"', "secrets", "services/proxy", "pods/exec", "pods/portforward", '"create"', '"delete"', '"patch"', '"update"']:
            self.assertNotIn(forbidden, result)


if __name__ == "__main__":
    unittest.main()
