"""Check webhook startup ordering in OpenTofu's actual dependency graph.

Run from an initialized, backend-free copy of the add-ons module:
    python3 -B -m unittest discover -s tests -p 'test_helm_dependencies.py'
No AWS or Kubernetes requests are made.
"""

from collections import defaultdict
from pathlib import Path
import re
import subprocess
import unittest


class HelmDependenciesTest(unittest.TestCase):
    def test_service_releases_wait_for_load_balancer_webhook(self):
        result = subprocess.run(
            ["tofu", "graph"],
            cwd=Path(__file__).resolve().parents[1],
            text=True, capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        edges = defaultdict(set)
        for source, target in re.findall(
            r'"((?:\\.|[^"\\])*)"\s*->\s*"((?:\\.|[^"\\])*)"', result.stdout
        ):
            edges[source].add(target)

        # Follow transitive dependencies too: the contract is startup ordering,
        # regardless of whether a release waits directly or through another one.
        webhook = "[root] helm_release.lb_controller (expand)"
        for release in (
            "external_secrets", "kube_state_metrics", "loki", "prometheus",
            "grafana", "alloy", "otel_collector", "otel_logs_collector",
            "karpenter",
        ):
            with self.subTest(release=release):
                pending = [f"[root] helm_release.{release} (expand)"]
                visited = set()
                while pending:
                    node = pending.pop()
                    if node not in visited:
                        visited.add(node)
                        pending.extend(edges[node] - visited)
                self.assertTrue(webhook in visited, f"{release} can race webhook startup")


if __name__ == "__main__":
    unittest.main()
