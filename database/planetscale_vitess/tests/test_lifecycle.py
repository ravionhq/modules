"""Exercise the real provider against a local API double, without cloud resources.

Run `tofu init -backend=false` in the module, then:
  python3 -m unittest discover -s tests -v

This tests ordinary plan/apply, automatic import/resize, and state behavior,
not just HCL text. No targeted plan or separate bootstrap pipeline is used.
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
                api.keyspace = None
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
                if api.branch["deletion_protected"]:
                    status, result = 422, {"message": "Branch is deletion protected"}
                else:
                    api.branch = None
                    api.keyspace = None  # Also removes the keyspace if still present.
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
        values = dict(organization="acme", name="app", region="us-east",
                      manage_default_keyspace=False)
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
        return stdout if expected == 0 else stdout + stderr

    def plan(self, *args):
        self.tofu("plan", "-input=false", "-out=test.tfplan", *args)
        return json.loads(self.tofu("show", "-json", "test.tfplan"))

    def test_standard_first_plan_and_second_import_resize(self):
        self.exercise_lifecycle("PS_10", "PS_20")

    def test_metal_standard_import_and_disk_resize(self):
        self.exercise_lifecycle("M_160_D_METAL_110", "M_160_D_METAL_230")

    def test_legacy_targeted_first_plan_remains_compatible(self):
        # Older module definitions omit the internal flag and still run their
        # targeted first stage. The true default must preserve that workflow.
        self.set_variables(manage_default_keyspace=True)
        self.plan("-target=planetscale_vitess_branch.main")
        self.assertFalse(self.api.calls)

    def test_destroy_after_only_first_deployment(self):
        self.set_variables(deletion_protection_enabled=False)
        self.plan()
        self.tofu("apply", "-input=false", "test.tfplan")
        # Ravion now has branch_id, even though no keyspace import has run.
        self.set_variables(manage_default_keyspace=True, deletion_protection_enabled=False)
        self.plan("-destroy")
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertIsNone(self.api.branch)
        self.assertIsNone(self.api.keyspace)
        self.assertFalse(any(method == "DELETE" and "/keyspaces/" in path
                             for method, path, _ in self.api.calls))

    def exercise_lifecycle(self, initial_size, resized_size):
        address = "planetscale_vitess_keyspace.main[0]"
        self.set_variables(cluster_size=initial_size)
        first = self.plan()
        self.assertFalse(self.api.calls, "A fresh full plan must not read a nonexistent keyspace")
        self.assertFalse(any("importing" in r["change"] for r in first["resource_changes"]))
        self.assertNotIn(address, [r["address"] for r in first["resource_changes"]])
        self.tofu("apply", "-input=false", "test.tfplan")
        outputs = json.loads(self.tofu("output", "-json"))
        self.assertEqual(outputs["keyspace"]["value"], "app")
        self.assertEqual(outputs["cluster_size"]["value"], initial_size)
        self.assertFalse(outputs["default_keyspace_managed"]["value"])
        self.assertTrue(outputs["password"]["sensitive"])
        self.assertTrue(outputs["connection_string"]["sensitive"])
        self.assertIn("p%40ss%2Fword", outputs["connection_string"]["value"])
        password_id = self.api.password["id"]

        # Retrying the first deployment with unchanged inputs is safe.
        retry = self.plan()
        self.assertTrue(all(r["change"]["actions"] == ["no-op"]
                            for r in retry["resource_changes"] if r["mode"] == "managed"))

        # Import and resize happen in the SAME normal plan/apply. Changing branch
        # settings at the same time must not make the import ID unknown.
        self.set_variables(cluster_size=resized_size, manage_default_keyspace=True,
                           extra_replicas=2, safe_migrations_enabled=False,
                           deletion_protection_enabled=False)
        second = self.plan()
        keyspace = next(r for r in second["resource_changes"] if r["address"] == address)
        self.assertIn("importing", keyspace["change"])
        self.assertEqual(keyspace["change"]["actions"], ["update"])
        branch = next(r for r in second["resource_changes"]
                      if r["address"] == "planetscale_vitess_branch.main")
        self.assertEqual(branch["change"]["actions"], ["update"])
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertEqual(self.api.keyspace["cluster_name"], resized_size)
        self.assertEqual(self.api.keyspace["extra_replicas"], 2)
        self.assertFalse(self.api.branch["deletion_protected"])
        self.assertFalse(self.api.branch["safe_migrations"])
        self.assertEqual(self.api.password["id"], password_id)
        self.assertTrue(json.loads(self.tofu("output", "-json"))["default_keyspace_managed"]["value"])
        self.assertFalse(any(method == "POST" and path.endswith("/keyspaces")
                             for method, path, _ in self.api.calls))
        self.assertFalse(any(method == "DELETE" for method, _, _ in self.api.calls))
        self.assertEqual(sum(method == "POST" and path.endswith("/branches")
                             for method, path, _ in self.api.calls), 1)

        final = self.plan()
        self.assertTrue(all(r["change"]["actions"] == ["no-op"] for r in final["resource_changes"]
                            if r["mode"] == "managed"))

        # Existing users of the old unindexed resource upgrade via the moved
        # block, without re-importing, deleting, or recreating the keyspace.
        self.tofu("state", "mv", address, "planetscale_vitess_keyspace.main")
        # Legacy module versions do not pass the new internal flag. Its true
        # default must preserve their managed keyspace, never plan deletion.
        variables = self.directory / "test.auto.tfvars.json"
        legacy_values = json.loads(variables.read_text())
        legacy_values.pop("manage_default_keyspace")
        variables.write_text(json.dumps(legacy_values))
        upgrade = self.plan()
        migrated = next(r for r in upgrade["resource_changes"] if r["address"] == address)
        self.assertEqual(migrated["previous_address"], "planetscale_vitess_keyspace.main")
        self.assertEqual(migrated["change"]["actions"], ["no-op"])
        self.assertNotIn("importing", migrated["change"])
        self.tofu("apply", "-input=false", "test.tfplan")

        # Recover missing keyspace state with an import-only apply.
        self.tofu("state", "rm", address)
        recovery = self.plan()
        recovered = next(r for r in recovery["resource_changes"] if r["address"] == address)
        self.assertIn("importing", recovered["change"])
        self.assertEqual(recovered["change"]["actions"], ["no-op"])
        self.tofu("apply", "-input=false", "test.tfplan")

        # External keyspace drift is corrected in place, not by replacing the branch.
        self.api.keyspace["cluster_name"] = initial_size
        self.api.keyspace["extra_replicas"] = 0
        drift = self.plan()
        changed = {r["address"]: r["change"]["actions"] for r in drift["resource_changes"]
                   if r["mode"] == "managed" and r["change"]["actions"] != ["no-op"]}
        self.assertEqual(changed, {address: ["update"]})
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertEqual(self.api.keyspace["cluster_name"], resized_size)
        self.assertEqual(self.api.keyspace["extra_replicas"], 2)

        self.set_variables(cluster_size=resized_size, manage_default_keyspace=True,
                           additional_passwords={"application": {}})
        error = self.tofu("plan", "-input=false", expected=1)
        self.assertIn("An additional password cannot have the same name", error)
        self.set_variables(cluster_size=resized_size, manage_default_keyspace=True,
                           extra_replicas=2, safe_migrations_enabled=False,
                           deletion_protection_enabled=False)
        # The mock allows default-keyspace DELETE before branch DELETE; a live
        # disposable database must still verify this real PlanetScale behavior.
        destruction = self.plan("-destroy")
        self.assertTrue(all(r["change"]["actions"] == ["delete"]
                            for r in destruction["resource_changes"] if r["mode"] == "managed"))
        self.assertIn(address, [r["address"] for r in destruction["resource_changes"]])
        self.tofu("apply", "-input=false", "test.tfplan")
        self.assertIsNone(self.api.branch)
        self.assertIsNone(self.api.keyspace)
        deletes = [path for method, path, _ in self.api.calls if method == "DELETE"]
        branch_deletes = [i for i, path in enumerate(deletes)
                          if "/branches/" in path and "/keyspaces/" not in path
                          and "/passwords/" not in path]
        self.assertEqual(len(branch_deletes), 1)
        self.assertLess(next(i for i, path in enumerate(deletes) if "/keyspaces/" in path),
                        branch_deletes[0])


if __name__ == "__main__":
    unittest.main()
