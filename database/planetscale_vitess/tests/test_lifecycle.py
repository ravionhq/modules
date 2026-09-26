"""Exercise the real provider against a local API double, without cloud resources.

Run `tofu init -backend=false` in the module, then:
  python3 -m unittest discover -s tests -v

This tests Terraform's actual import/target/state behavior, not just HCL text.
It is not a substitute for a live PlanetScale acceptance run.
"""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


MODULE = Path(__file__).resolve().parents[1]


class API(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def handle_request(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        url = urlsplit(self.path)
        path = url.path
        api = self.server
        api.calls.append((self.command, path, body))
        status = 200
        result = {}
        if path.endswith("/branches") and self.command == "POST":
            api.branch = dict(body, id="branch1", ready=True, state="ready",
                              cluster_name=body["cluster_size"],
                              region={"id": "us-east", "mysql_supported": True},
                              html_url="https://app.planetscale.com/acme/app/main")
            api.keyspace = dict(id="keyspace1", name="app", default=True,
                                cluster_name=body["cluster_size"], extra_replicas=0,
                                shards=1, ready=True, resizing=False, resize_pending=False,
                                config_change_in_progress=False)
            result, status = api.branch, 201
        elif path.endswith("/safe-migrations"):
            api.branch.update(body)
            result = api.branch
        elif "/keyspaces/" in path and path.endswith("/resizes"):
            api.keyspace.update(body)
            api.keyspace["cluster_name"] = body["cluster_size"]
            result = {"id": "resize1"}
        elif path.endswith("/resizes"):
            result = {"id": "resize1", "state": "completed"}
        elif "/resizes/" in path:
            result = {"id": "resize1", "state": "completed"}
        elif path.endswith("/keyspaces"):
            if self.command != "GET":
                status, result = 422, {"message": "Default keyspace already exists"}
            elif api.branch is None:
                status = 404
            else:
                page = int(parse_qs(url.query).get("page", ["1"])[0])
                result = {"type": "list", "data": [api.keyspace] if page == 1 else []}
        elif "/keyspaces/" in path:
            if self.command == "DELETE":
                status = 204
            else:
                result = api.keyspace
        elif path.endswith("/passwords") and self.command == "POST":
            api.password = dict(body, id="password1", username="user1",
                                plain_text="p@ss/word", access_host_url="example.psdb.cloud")
            result, status = api.password, 201
        elif "/passwords/" in path:
            if self.command == "DELETE":
                status = 204
            else:
                result = dict(api.password)
                result.pop("plain_text", None)
        elif "/branches/" in path:
            if api.branch is None:
                status = 404
            elif self.command == "DELETE":
                api.branch = None
                status = 204
            else:
                if self.command == "PATCH":
                    api.branch.update(body)
                result = api.branch
        else:
            status = 404
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if status != 204:
            self.wfile.write(json.dumps(result).encode())

    do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = handle_request


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="planetscale-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        for path in MODULE.glob("*.tf"):
            # Production uses Ravion state. The API double always uses local state.
            (self.directory / path.name).write_text(path.read_text().replace("cloud {}", ""))
        shutil.copy(MODULE / ".terraform.lock.hcl", self.directory)
        self.api = ThreadingHTTPServer(("127.0.0.1", 0), API)
        self.api.branch = self.api.keyspace = self.api.password = None
        self.api.calls = []
        self.thread = threading.Thread(target=self.api.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("TF_", "TOFU_", "PLANETSCALE_"))}
        self.env.update({
            "PLANETSCALE_SERVICE_TOKEN_ID": "test-token-id",
            "PLANETSCALE_SERVICE_TOKEN": "test-token",
            "PLANETSCALE_SERVER_URL": f"http://127.0.0.1:{self.api.server_port}",
            "TF_IN_AUTOMATION": "1",
        })
        self.set_variables()
        self.tofu("init", "-backend=false", "-input=false", "-lockfile=readonly",
                  f"-plugin-dir={MODULE / '.terraform/providers'}")

    def stop_server(self):
        self.api.shutdown()
        self.api.server_close()
        self.thread.join()

    def set_variables(self, **overrides):
        values = dict(organization="acme", name="app", region="us-east")
        values.update(overrides)
        (self.directory / "test.auto.tfvars.json").write_text(json.dumps(values))

    def tofu(self, *args, expected=0):
        process = subprocess.Popen(["tofu", *args, "-no-color"], cwd=self.directory,
                                   env=self.env, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            # The real provider waits 30 seconds before polling ready resources.
            stdout, stderr = process.communicate(timeout=75)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            self.fail(f"Timed out: {args}\n{stdout}\n{stderr}\nLast API calls: {self.api.calls[-15:]}")
        self.assertEqual(process.returncode, expected, stdout + stderr)
        return stdout

    def plan(self, *args):
        self.tofu("plan", "-input=false", "-out=test.tfplan", *args)
        return json.loads(self.tofu("show", "-json", "test.tfplan"))

    def test_bootstrap_import_retry_and_resize(self):
        plan = self.plan("-target=planetscale_vitess_branch.main")
        changes = {r["address"]: r["change"]["actions"] for r in plan["resource_changes"]}
        self.assertEqual(changes, {"planetscale_vitess_branch.main": ["create"]})
        self.assertFalse(self.api.calls, "Bootstrap plan must not try to import a nonexistent keyspace")
        self.tofu("apply", "-input=false", "test.tfplan")

        # A failed/cancelled stage two must be recoverable: repeating bootstrap
        # must leave the existing branch alone and still permit the import.
        retry = self.plan("-target=planetscale_vitess_branch.main")
        self.assertTrue(all(r["change"]["actions"] == ["no-op"] for r in retry["resource_changes"]))
        plan = self.plan()
        keyspace = next(r for r in plan["resource_changes"] if r["address"] == "planetscale_vitess_keyspace.main")
        self.assertIn("importing", keyspace["change"])
        self.assertNotIn("create", keyspace["change"]["actions"])
        self.tofu("apply", "-input=false", "test.tfplan")

        self.set_variables(cluster_size="PS_20")
        bootstrap = self.plan("-target=planetscale_vitess_branch.main")
        self.assertTrue(all(r["change"]["actions"] == ["no-op"] for r in bootstrap["resource_changes"]))
        resized = self.plan()
        changed = {r["address"]: r["change"]["actions"] for r in resized["resource_changes"]
                   if r["mode"] == "managed" and r["change"]["actions"] != ["no-op"]}
        self.assertEqual(changed, {"planetscale_vitess_keyspace.main": ["update"]})
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertEqual(self.api.keyspace["cluster_name"], "PS_20")
        self.assertFalse(any(method == "POST" and path.endswith("/keyspaces")
                             for method, path, _ in self.api.calls))
        self.assertFalse(any(method == "DELETE" for method, _, _ in self.api.calls))
        self.assertEqual(sum(method == "POST" and path.endswith("/branches")
                             for method, path, _ in self.api.calls), 1)

        final = self.plan()
        self.assertTrue(all(r["change"]["actions"] == ["no-op"] for r in final["resource_changes"]
                            if r["mode"] == "managed"))
        outputs = json.loads(self.tofu("output", "-json"))
        self.assertTrue(outputs["password"]["sensitive"])
        self.assertTrue(outputs["connection_string"]["sensitive"])
        self.assertIn("p%40ss%2Fword", outputs["connection_string"]["value"])

        # Losing only the keyspace state must recover through an import-only
        # plan, not a duplicate keyspace or credential recreation.
        self.tofu("state", "rm", "planetscale_vitess_keyspace.main")
        recovery = self.plan()
        recovered_keyspace = next(r for r in recovery["resource_changes"]
                                  if r["address"] == "planetscale_vitess_keyspace.main")
        self.assertIn("importing", recovered_keyspace["change"])
        self.assertEqual(recovered_keyspace["change"]["actions"], ["no-op"])
        self.tofu("apply", "-input=false", "test.tfplan")

        # Branch settings are reconciled before the full plan, so discovery is
        # known during the import plan even when safe migrations/protection change.
        self.set_variables(cluster_size="PS_20", safe_migrations_enabled=False,
                           deletion_protection_enabled=False)
        self.plan("-target=planetscale_vitess_branch.main")
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertFalse(self.api.branch["deletion_protected"])
        self.assertFalse(self.api.branch["safe_migrations"])
        self.plan()
        self.tofu("apply", "-input=false", "test.tfplan")
        destruction = self.plan("-destroy")
        self.assertTrue(all(r["change"]["actions"] == ["delete"]
                            for r in destruction["resource_changes"] if r["mode"] == "managed"))
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertIsNone(self.api.branch)


if __name__ == "__main__":
    unittest.main()
