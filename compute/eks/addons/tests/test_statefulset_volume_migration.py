"""Offline tests for the StatefulSet volume migration Job's script.

A fake kubectl answers from a small in-memory description of the cluster and
records every delete; a fake wget records flushes. Nothing reaches a cluster.

Run from the repository root:
    python3 -B -m unittest discover -s compute/eks/addons/tests -p 'test_statefulset_volume_migration.py'
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "charts/statefulset-volume-migration/files/migrate.sh"

# Answers `kubectl get statefulset|pod NAME ... -o go-template=...` from
# $CLUSTER (JSON) in the shapes the script's templates print, and records
# every delete in $CALLS.
FAKE_KUBECTL = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
cluster = json.loads(os.environ["CLUSTER"])
with open(os.environ["CALLS"], "a") as calls:
    calls.write(" ".join(["kubectl"] + args) + "\n")
verb, kind, name = args[0], args[1], args[2]
if verb == "get" and kind == "statefulset":
    sts = cluster.get("statefulset")
    if sts is None:
        sys.exit(0)  # --ignore-not-found prints nothing
    print(f'{sts["replicas"]} {"".join(t + "," for t in sts["claimTemplates"])}', end="")
elif verb == "get" and kind == "pod":
    pod = cluster.get("pods", {}).get(name)
    if pod is None:
        sys.exit(0)
    print("present " + "".join(c + " " for c in pod), end="")
elif verb == "delete":
    if os.environ.get("FAIL_DELETE") == "1":
        sys.exit(1)
else:
    sys.exit(2)
"""

FAKE_WGET = r"""#!/bin/sh
echo "wget $*" >> "$CALLS"
[ "${FAIL_FLUSH:-0}" = 1 ] && exit 1
exit 0
"""


class MigrateTests(unittest.TestCase):
    def run_job(self, cluster, persistent, flush_url="http://loki:3100/flush", **env_extra):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, body in (("kubectl", FAKE_KUBECTL), ("wget", FAKE_WGET)):
                tool = root / name
                tool.write_text(body)
                tool.chmod(0o755)
            calls = root / "calls"
            env = dict(
                os.environ,
                PATH=f"{root}:{os.environ['PATH']}",
                CLUSTER=json.dumps(cluster),
                CALLS=str(calls),
                STATEFULSET="ravion-loki",
                NAMESPACE="ravion-operator",
                PERSISTENT="true" if persistent else "false",
                FLUSH_URL=flush_url,
                **env_extra,
            )
            result = subprocess.run(["sh", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=10)
            lines = calls.read_text().splitlines() if calls.exists() else []
            return result, [line for line in lines if not line.startswith("kubectl get")]

    def test_missing_statefulset_is_left_alone(self):
        result, actions = self.run_job({}, persistent=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, [])

    def test_layout_change_deletes_the_statefulset_and_its_pods_after_a_flush(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": []}, "pods": {"ravion-loki-0": []}},
            persistent=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(actions), 2, actions)
        self.assertTrue(actions[0].startswith("wget ") and "http://loki:3100/flush" in actions[0], actions)
        # Foreground: the pods go with it, so the recreated StatefulSet creates
        # new ones with the new volumes instead of adopting the old ones.
        self.assertIn("delete statefulset ravion-loki", actions[1])
        self.assertIn("--namespace=ravion-operator", actions[1])
        self.assertIn("--cascade=foreground", actions[1])
        self.assertNotIn("--cascade=orphan", actions[1])
        self.assertIn("--wait", actions[1])

    def test_layout_change_back_to_ephemeral_also_recreates(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": ["storage"]},
             "pods": {"ravion-loki-0": ["storage-ravion-loki-0"]}},
            persistent=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("delete statefulset ravion-loki" in a and "--cascade=foreground" in a for a in actions), actions)

    def test_matching_layout_with_mounted_claims_changes_nothing(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": ["storage"]},
             "pods": {"ravion-loki-0": ["storage-ravion-loki-0"]}},
            persistent=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, [])

    def test_pod_adopted_without_its_claim_is_replaced(self):
        # What chart 0.1.0 left behind: the StatefulSet has the claim template,
        # its adopted pod still runs on the old emptyDir, and the controller
        # cannot add the volume in place, so it never replaces the pod.
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": ["storage"]}, "pods": {"ravion-loki-0": []}},
            persistent=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(actions), 2, actions)
        self.assertTrue(actions[0].startswith("wget "), actions)
        self.assertIn("delete pod ravion-loki-0", actions[1])
        self.assertIn("--namespace=ravion-operator", actions[1])
        self.assertFalse(any("delete statefulset" in a for a in actions), actions)

    def test_only_the_pods_missing_a_claim_are_replaced(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 3, "claimTemplates": ["storage"]},
             "pods": {"ravion-loki-0": ["storage-ravion-loki-0"], "ravion-loki-1": [], "ravion-loki-2": ["storage-ravion-loki-2"]}},
            persistent=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        deletes = [a for a in actions if a.startswith("kubectl delete")]
        self.assertEqual(len(deletes), 1, actions)
        self.assertIn("delete pod ravion-loki-1 ", deletes[0] + " ")

    def test_missing_pod_is_skipped(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": ["storage"]}, "pods": {}},
            persistent=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, [])

    def test_no_flush_without_a_flush_url(self):
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": []}, "pods": {"ravion-loki-0": []}},
            persistent=True,
            flush_url="",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(a.startswith("wget") for a in actions), actions)
        self.assertTrue(any("delete statefulset" in a for a in actions), actions)

    def test_failed_flush_is_reported_and_the_migration_continues(self):
        # A flush that fails usually means the store is already down, with
        # nothing left in memory to lose; refusing would leave the layout stuck.
        result, actions = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": []}, "pods": {"ravion-loki-0": []}},
            persistent=True,
            FAIL_FLUSH="1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("flush", (result.stdout + result.stderr).lower())
        self.assertTrue(any("delete statefulset" in a for a in actions), actions)

    def test_failed_delete_fails_the_job(self):
        result, _ = self.run_job(
            {"statefulset": {"replicas": 1, "claimTemplates": []}, "pods": {"ravion-loki-0": []}},
            persistent=True,
            FAIL_DELETE="1",
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
