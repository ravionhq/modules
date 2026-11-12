"""Check NLB startup ordering without initializing the module's cloud backend."""

from collections import defaultdict
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[1]


class NlbDependenciesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        repo = MODULE.parents[1]
        manifest = json.loads((MODULE / ".terraform/modules/modules.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            scratch = package / MODULE.relative_to(repo)
            for entry in manifest["Modules"]:
                original = (MODULE / entry["Dir"]).resolve()
                target = package / original.relative_to(repo)
                target.mkdir(parents=True, exist_ok=True)
                for source in original.glob("*.tf"):
                    content = source.read_text()
                    if original == MODULE:
                        content = re.sub(r"\bcloud\s*\{\s*\}", "", content)
                    (target / source.name).write_text(content)
            shutil.copy2(MODULE / ".terraform.lock.hcl", scratch)
            providers = MODULE / ".terraform/providers"
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

    def test_ecs_waits_for_every_nlb_listener(self):
        pending = ["[root] aws_ecs_service.this (expand)"]
        visited = set()
        while pending:
            node = pending.pop()
            if node not in visited:
                visited.add(node)
                pending.extend(self.edges[node] - visited)
        for listener in ("nlb", "nlb_additional"):
            with self.subTest(listener=listener):
                self.assertIn(f"[root] aws_lb_listener.{listener} (expand)", visited)

    def test_nlb_listener_actions_remain_terraform_managed(self):
        source = (MODULE / "listener_rules.tf").read_text()
        for listener in ("nlb", "nlb_additional"):
            with self.subTest(listener=listener):
                block = re.search(
                    rf'^resource "aws_lb_listener" "{listener}" \{{.*?^\}}',
                    source, re.MULTILINE | re.DOTALL,
                ).group()
                self.assertNotRegex(block, r"ignore_changes\s*=\s*\[[^\]]*default_action")
                self.assertNotRegex(block, r"ignore_changes\s*=\s*all")


if __name__ == "__main__":
    unittest.main()
