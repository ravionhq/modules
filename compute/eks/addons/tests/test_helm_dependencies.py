"""Check webhook startup ordering in OpenTofu's actual dependency graph.

Run from an initialized add-ons module:
    python3 -B -m unittest discover -s tests -p 'test_helm_dependencies.py'
Builds a backend-free scratch configuration; no AWS or Kubernetes requests.
"""

from collections import defaultdict
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


class HelmDependenciesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module = Path(__file__).resolve().parents[1]
        repo = module.parents[2]
        # Never initialize the module's real cloud backend just to inspect its
        # graph. Preserve local-module paths in a TF-only copy of the package.
        manifest = json.loads((module / ".terraform/modules/modules.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            scratch = package / module.relative_to(repo)
            for entry in manifest["Modules"]:
                original = (module / entry["Dir"]).resolve()
                target = package / original.relative_to(repo)
                target.mkdir(parents=True, exist_ok=True)
                for source in original.glob("*.tf"):
                    content = source.read_text()
                    if original == module:
                        content = re.sub(r"\bcloud\s*\{\s*\}", "", content)
                    (target / source.name).write_text(content)
            shutil.copy2(module / ".terraform.lock.hcl", scratch)
            providers = module / ".terraform/providers"
            if providers.exists():
                (scratch / ".terraform").mkdir()
                (scratch / ".terraform/providers").symlink_to(providers, target_is_directory=True)
            initialized = subprocess.run(
                ["tofu", "init", "-backend=false", "-lockfile=readonly"],
                cwd=scratch, text=True, capture_output=True, timeout=120,
            )
            if initialized.returncode != 0:
                raise RuntimeError(initialized.stderr)
            result = subprocess.run(
                ["tofu", "graph"], cwd=scratch,
                text=True, capture_output=True, timeout=60,
            )
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        cls.edges = defaultdict(set)
        for source, target in re.findall(
            r'"((?:\\.|[^"\\])*)"\s*->\s*"((?:\\.|[^"\\])*)"', result.stdout
        ):
            cls.edges[source].add(target)

    def dependencies(self, resource):
        pending = [f"[root] {resource} (expand)"]
        visited = set()
        while pending:
            node = pending.pop()
            if node not in visited:
                visited.add(node)
                pending.extend(self.edges[node] - visited)
        return visited

    def test_controller_waits_for_crd_adoption_and_upgrade(self):
        self.assertIn(
            "[root] helm_release.lb_controller_crds (expand)",
            self.dependencies("helm_release.lb_controller"),
        )
        self.assertIn(
            "[root] data.helm_template.lb_controller (expand)",
            self.dependencies("helm_release.lb_controller_crds"),
        )

    def test_service_releases_wait_for_load_balancer_webhook(self):

        # Follow transitive dependencies too: the contract is startup ordering,
        # regardless of whether a release waits directly or through another one.
        webhook = "[root] helm_release.lb_controller (expand)"
        for release in (
            "external_secrets", "kube_state_metrics", "loki", "prometheus",
            "grafana", "alloy", "otel_collector", "otel_logs_collector",
            "karpenter",
        ):
            with self.subTest(release=release):
                visited = self.dependencies(f"helm_release.{release}")
                self.assertTrue(webhook in visited, f"{release} can race webhook startup")


if __name__ == "__main__":
    unittest.main()
