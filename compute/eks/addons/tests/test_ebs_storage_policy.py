"""Regression checks for fail-closed StatefulSet expansion admission."""
from pathlib import Path
import subprocess
import unittest

CHART = Path(__file__).resolve().parents[1] / "charts/ebs-storage"


class StoragePolicyTests(unittest.TestCase):
    def render(self, *args):
        return subprocess.check_output(
            ["helm", "template", "test", str(CHART),
             "--show-only", "templates/admission-policy.yaml", *args], text=True,
        )

    def test_only_managed_expandable_class_is_mutated(self):
        policy = self.render()
        self.assertIn('t.spec.storageClassName == "gp3"', policy)
        self.assertIn('oldObject.spec.volumeClaimTemplates.all(t,', policy)
        self.assertIn('has(t.spec.storageClassName)', policy)

    def test_disabled_storage_class_does_not_accept_growth(self):
        policy = self.render("--set", "storageClass.enabled=false")
        self.assertIn("- name: expandable-storage-class\n      expression: >-\n        false", policy)


if __name__ == "__main__":
    unittest.main()
