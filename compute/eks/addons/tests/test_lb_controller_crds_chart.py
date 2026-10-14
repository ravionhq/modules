"""Render the CRD wrapper without a cluster. Requires Helm and yq v4.

Run: python3 -B -m unittest discover -s tests -p 'test_lb_controller_crds_chart.py'
"""

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts/aws-load-balancer-controller-crds"


class LoadBalancerCRDsChartTest(unittest.TestCase):
    @staticmethod
    def crd(name, annotations=None):
        return {
            "apiVersion": "apiextensions.k8s.io/v1",
            "kind": "CustomResourceDefinition",
            "metadata": {"name": f"{name}.elbv2.k8s.aws", "annotations": annotations or {}},
            "spec": {
                "group": "elbv2.k8s.aws", "scope": "Namespaced",
                "names": {"plural": name, "singular": name, "kind": "TestBinding"},
                "versions": [{"name": "v1beta1", "served": True, "storage": True,
                              "schema": {"openAPIV3Schema": {"type": "object"}}}],
            },
        }

    def render(self, files, success=True):
        with tempfile.TemporaryDirectory() as directory:
            values = Path(directory) / "values.json"
            values.write_text(json.dumps({"crds": files}))
            result = subprocess.run([
                "helm", "template", "aws-load-balancer-controller-crds", str(CHART),
                "--namespace", "kube-system", "--values", str(values),
            ], text=True, capture_output=True, timeout=30)
        if not success:
            self.assertNotEqual(result.returncode, 0, "Invalid CRD input must fail closed")
            return result.stderr
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = subprocess.run([
            "yq", "ea", "-o=json", "-I=0", "[.] | map(select(. != null))", "-",
        ], input=result.stdout, text=True, capture_output=True, timeout=30)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        return json.loads(parsed.stdout)

    def test_every_crd_is_retained_without_changing_the_upstream_schema(self):
        crds = [self.crd("targetgroupbindings"),
                self.crd("ingressclassparams", {"upstream.example/annotation": "preserve"})]
        # Upstream files can contain several YAML documents, leading separators,
        # comments and trailing empty documents, or be separate files.
        for files in (
            ["# upstream\n---\n" + "\n---\n".join(map(json.dumps, crds)) + "\n---\n"],
            list(map(json.dumps, crds)),
            ["\r\n--- \r\n" + "\r\n---\t\r\n".join(map(json.dumps, crds))],
        ):
            with self.subTest(files=files):
                expected = deepcopy(crds)
                for crd in expected:
                    crd["metadata"]["annotations"]["helm.sh/resource-policy"] = "keep"
                self.assertEqual(self.render(files), expected)

    def test_upstream_delete_policy_cannot_override_retention(self):
        crd = self.crd("targetgroupbindings", {"helm.sh/resource-policy": "delete"})
        output = self.render([json.dumps(crd)])
        self.assertEqual(output[0]["metadata"]["annotations"]["helm.sh/resource-policy"], "keep")

    def test_non_crd_resources_are_rejected(self):
        error = self.render([json.dumps({"kind": "Deployment"})], success=False)
        self.assertIn("may only contain CustomResourceDefinition", error)

    def test_malformed_yaml_is_rejected(self):
        self.render(["kind: [invalid"], success=False)

    def test_missing_upstream_crds_are_rejected(self):
        self.assertIn("crds must contain", self.render([], success=False))


if __name__ == "__main__":
    unittest.main()
