import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "read_scaling", Path(__file__).parents[1] / "modules/eks_node_group/scripts/read_scaling.py"
)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def response(payload=None, error=""):
    return subprocess.CompletedProcess([], 1 if error else 0, json.dumps(payload), error)


class ScalingReaderTest(unittest.TestCase):
    query = {
        "cluster_name": "test-cluster", "node_group_name": "system",
        "region": "us-east-2", "account_id": "123456789012",
    }
    identity = response({"Account": "123456789012"})

    def test_preserves_live_capacity_including_zero(self):
        for desired in (0, 2, 8):
            with self.subTest(desired=desired), patch.object(
                reader.subprocess, "run", side_effect=[self.identity, response({"nodegroup": {
                    "nodegroupArn": "arn:aws:eks:us-east-2:123456789012:nodegroup/test-cluster/system/id",
                    "scalingConfig": {"desiredSize": desired},
                }})]
            ) as aws:
                self.assertEqual(reader.read_scaling(self.query), {"exists": "true", "desired_size": str(desired)})
                args = aws.call_args.args[0]
                self.assertIn("describe-nodegroup", args)
                self.assertEqual(args[args.index("--region") + 1], "us-east-2")
                self.assertEqual(args[args.index("--nodegroup-name") + 1], "system")

    def test_only_explicit_nodegroup_not_found_uses_creation_defaults(self):
        error = "An error occurred (ResourceNotFoundException) when calling the DescribeNodegroup operation: No node group"
        with patch.object(reader.subprocess, "run", side_effect=[self.identity, response(error=error)]):
            self.assertEqual(reader.read_scaling(self.query), {"exists": "false", "desired_size": "0"})

    def test_errors_do_not_reset_live_capacity(self):
        for error in ("AccessDeniedException", "ExpiredTokenException", "ThrottlingException", "connection failed", "ResourceNotFoundException from a different operation"):
            with self.subTest(error=error), patch.object(reader.subprocess, "run", side_effect=[self.identity, response(error=error)]):
                with self.assertRaises(RuntimeError):
                    reader.read_scaling(self.query)

    def test_account_mismatch_fails_before_lookup(self):
        with patch.object(reader.subprocess, "run", return_value=response({"Account": "999999999999"})) as aws:
            with self.assertRaisesRegex(RuntimeError, "credentials do not match"):
                reader.read_scaling(self.query)
            self.assertEqual(aws.call_count, 1)

    def test_malformed_success_is_not_treated_as_absent(self):
        with patch.object(reader.subprocess, "run", side_effect=[self.identity, response({})]):
            with self.assertRaises(KeyError):
                reader.read_scaling(self.query)

    def test_timeout_stops_plan(self):
        with patch.object(reader.subprocess, "run", side_effect=subprocess.TimeoutExpired("aws", 60)):
            with self.assertRaises(subprocess.TimeoutExpired):
                reader.read_scaling(self.query)


if __name__ == "__main__":
    unittest.main()
