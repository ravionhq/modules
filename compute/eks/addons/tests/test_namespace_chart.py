"""Render the real namespace chart against a read-only fake Kubernetes API.

Run: python3 -B -m unittest discover -s tests -p 'test_namespace_chart.py'
Requires Helm; never uses the developer's Kubernetes context.
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import subprocess
import tempfile
from threading import Thread
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts/ravion-operator-namespaces"
RELEASE = "ravion-operator-namespaces"


class NamespaceChartTest(unittest.TestCase):
    def render(self, namespaces, existing=None, helm_inventory_namespaces=None):
        existing = existing or {}
        reads = []

        class API(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                path = self.path.split("?")[0]
                status = 200
                if path == "/version":
                    body = {"major": "1", "minor": "34", "gitVersion": "v1.34.0"}
                elif path == "/api":
                    body = {"kind": "APIVersions", "apiVersion": "v1", "versions": ["v1"]}
                elif path == "/apis":
                    version = {"groupVersion": "rbac.authorization.k8s.io/v1", "version": "v1"}
                    body = {"kind": "APIGroupList", "apiVersion": "v1", "groups": [{
                        "name": "rbac.authorization.k8s.io", "versions": [version],
                        "preferredVersion": version,
                    }]}
                elif path == "/apis/rbac.authorization.k8s.io/v1":
                    body = {
                        "kind": "APIResourceList", "apiVersion": "v1",
                        "groupVersion": "rbac.authorization.k8s.io/v1",
                        "resources": [
                            {"name": "roles", "singularName": "role", "namespaced": True,
                             "kind": "Role", "verbs": ["get", "list"]},
                            {"name": "rolebindings", "singularName": "rolebinding", "namespaced": True,
                             "kind": "RoleBinding", "verbs": ["get", "list"]},
                        ],
                    }
                elif path == "/api/v1":
                    body = {
                        "kind": "APIResourceList", "apiVersion": "v1", "groupVersion": "v1",
                        "resources": [{"name": "namespaces", "singularName": "namespace",
                                       "namespaced": False, "kind": "Namespace",
                                       "verbs": ["get", "list"]}],
                    }
                else:
                    name = path.removeprefix("/api/v1/namespaces/")
                    reads.append(name)
                    body = existing.get(name)
                    if body is None:
                        status = 404
                        body = {"kind": "Status", "apiVersion": "v1", "status": "Failure",
                                "reason": "NotFound", "code": 404}
                encoded = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

        server = ThreadingHTTPServer(("127.0.0.1", 0), API)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                directory = Path(directory)
                kubeconfig = directory / "kubeconfig.json"
                kubeconfig.write_text(json.dumps({
                    "apiVersion": "v1", "kind": "Config",
                    "clusters": [{"name": "test", "cluster": {
                        "server": f"http://127.0.0.1:{server.server_port}"}}],
                    "contexts": [{"name": "test", "context": {"cluster": "test", "user": "test"}}],
                    "current-context": "test", "users": [{"name": "test", "user": {}}],
                }))
                kubeconfig.chmod(0o600)
                values = directory / "values.json"
                values.write_text(json.dumps({
                    "namespaces": namespaces,
                    "helmInventoryNamespaces": helm_inventory_namespaces or [],
                }))
                result = subprocess.run([
                    "helm", "template", RELEASE, str(CHART), "--namespace", "kube-system",
                    "--kubeconfig", str(kubeconfig), "--dry-run=server", "--disable-openapi-validation",
                    "--values", str(values),
                ], text=True, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(set(namespaces).issubset(reads), "Helm must actually perform namespace lookups")
                return result.stdout
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_missing_namespace_is_created_once_and_retained(self):
        output = self.render(["rvn-app", "rvn-app"])
        self.assertEqual(output.count("kind: Namespace"), 1)
        self.assertIn('name: "rvn-app"', output)
        self.assertIn("helm.sh/resource-policy: keep", output)

    def test_existing_external_namespace_is_not_adopted(self):
        output = self.render(["rvn-app"], {"rvn-app": {
            "apiVersion": "v1", "kind": "Namespace", "metadata": {"name": "rvn-app"},
        }})
        self.assertNotIn("kind: Namespace", output)

    def test_namespace_owned_by_another_release_is_not_adopted(self):
        output = self.render(["rvn-app"], {"rvn-app": self.owned_namespace("other")})
        self.assertNotIn("kind: Namespace", output)

    def test_owned_namespace_remains_in_manifest_on_upgrade(self):
        output = self.render(["rvn-app"], {"rvn-app": self.owned_namespace(RELEASE)})
        self.assertIn('name: "rvn-app"', output)
        self.assertIn("helm.sh/resource-policy: keep", output)

    def test_helm_secrets_are_readable_only_through_scoped_namespace_roles(self):
        output = self.render(["deployed", "observed"], helm_inventory_namespaces=[
            "deployed", "observed", "deployed",
        ])
        roles = [doc for doc in output.split("---") if re.search(r"^kind: Role$", doc, re.MULTILINE)]
        bindings = [doc for doc in output.split("---") if re.search(r"^kind: RoleBinding$", doc, re.MULTILINE)]
        self.assertEqual(len(roles), 2)
        self.assertEqual(len(bindings), 2)
        for namespace in ["deployed", "observed"]:
            role = next(doc for doc in roles if f'namespace: "{namespace}"' in doc)
            self.assertIn('resources: ["secrets"]', role)
            self.assertIn('verbs: ["get", "list"]', role)
            self.assertNotIn("resourceNames", role, "list cannot be restricted by Helm secret names or labels")
            self.assertNotIn("helm.sh/resource-policy", role, "removing scope must revoke the Role")
            binding = next(doc for doc in bindings if f'namespace: "{namespace}"' in doc)
            self.assertIn("kind: Group", binding)
            self.assertIn("name: ravion:readers", binding)
            self.assertIn("name: ravion-helm-inventory-read", binding)
            self.assertNotIn("helm.sh/resource-policy", binding)
        for forbidden in ["ClusterRole", '"*"', '"create"', '"update"', '"patch"', '"delete"', "pods/exec", "pods/portforward"]:
            self.assertNotIn(forbidden, output)
        self.assertEqual(output.count("helm.sh/resource-policy: keep"), 2, "keep belongs only to namespaces")

    def test_external_namespace_keeps_ownership_while_receiving_read_rbac(self):
        output = self.render(["rvn-app"], {"rvn-app": self.owned_namespace("other")}, ["rvn-app"])
        self.assertNotIn("kind: Namespace", output)
        self.assertIn('namespace: "rvn-app"', output)
        self.assertIn('resources: ["secrets"]', output)
        self.assertNotIn("meta.helm.sh/release-name", output)

    def test_external_creation_mode_still_renders_helm_read_roles(self):
        output = self.render([], helm_inventory_namespaces=["existing"])
        self.assertNotIn("kind: Namespace", output)
        self.assertIn('namespace: "existing"', output)
        self.assertIn('resources: ["secrets"]', output)

    def test_empty_scope_has_no_helm_secret_access(self):
        output = self.render(["retained"], helm_inventory_namespaces=[])
        self.assertIn("kind: Namespace", output)
        self.assertNotIn('resources: ["secrets"]', output)
        self.assertNotIn("kind: Role", output)

    @staticmethod
    def owned_namespace(release):
        return {"apiVersion": "v1", "kind": "Namespace", "metadata": {
            "name": "rvn-app", "labels": {"app.kubernetes.io/managed-by": "Helm"}, "annotations": {
                "meta.helm.sh/release-name": release,
                "meta.helm.sh/release-namespace": "kube-system",
            },
        }}


if __name__ == "__main__":
    unittest.main()
