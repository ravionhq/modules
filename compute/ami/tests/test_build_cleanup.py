import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


MODULE_DIR = Path(__file__).resolve().parents[1]
CLEANUP_SCRIPT = MODULE_DIR / "cleanup_build_resources.sh"
BUILD_CLEANUP_TF = MODULE_DIR / "build_cleanup.tf"
TOFU_BIN = os.environ.get("TOFU_BIN") or shutil.which("tofu")

ACCOUNT_ID = "123456789012"
INSTANCE_ID = "ami-instance-123"
IMAGE_VERSION_1 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image/base-image/1.0.0/1"
)
IMAGE_VERSION_2 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image/base-image/1.1.0/1"
)
IMAGE_BUILD_1 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image/base-image/1.0.0/1"
)
IMAGE_BUILD_2 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image/base-image/1.1.0/1"
)
IMAGE_BUILD_EXTERNAL = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image/other-image/1.0.0/1"
)
RECIPE_1 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image-recipe/ami-recipe/1.0.0"
)
RECIPE_2 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image-recipe/ami-recipe/1.1.0"
)
RECIPE_EXTERNAL = (
    "arn:aws:imagebuilder:us-west-2:123456789012:image-recipe/other-recipe/1.0.0"
)
COMPONENT_VERSION_1 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:component/ami-component/1.0.0/1"
)
COMPONENT_VERSION_2 = (
    "arn:aws:imagebuilder:us-west-2:123456789012:component/ami-component/1.1.0/1"
)
COMPONENT_VERSION_EXTERNAL = (
    "arn:aws:imagebuilder:us-west-2:123456789012:component/external/1.0.0/1"
)


FAKE_AWS = """\
#!/usr/bin/env python3
import json
import os
import sys


args = sys.argv[1:]
operation = " ".join(args[:2])
with open(os.environ["FAKE_AWS_LOG"], "a", encoding="utf-8") as log:
    log.write(json.dumps(args) + "\\n")


def option_value(option):
    return args[args.index(option) + 1]


with open(os.environ["FAKE_AWS_SCENARIO"], encoding="utf-8") as scenario_file:
    scenario = json.load(scenario_file)
error = scenario.get("failures", {}).get(operation)
if error:
    print(
        f"An error occurred ({error}) when calling the {args[1]} operation: fake failure",
        file=sys.stderr,
    )
    sys.exit(254)

if operation == "sts get-caller-identity":
    response = scenario["identity"]
elif operation == "imagebuilder list-images":
    response = scenario["images"]
elif operation == "imagebuilder list-image-build-versions":
    response = scenario["image_build_versions"].get(
        option_value("--image-version-arn"), {}
    )
elif operation == "imagebuilder list-image-recipes":
    response = scenario["recipes"]
elif operation == "imagebuilder list-components":
    response = scenario["components"]
elif operation == "imagebuilder list-component-build-versions":
    response = scenario["component_build_versions"].get(
        option_value("--component-version-arn"), {}
    )
elif operation in {
    "imagebuilder delete-image",
    "imagebuilder delete-image-recipe",
    "imagebuilder delete-component",
}:
    if os.environ.get("CLEANUP_TRACE"):
        with open(os.environ["CLEANUP_TRACE"], "a", encoding="utf-8") as trace:
            trace.write(f"delete:{args[1]}:{args[3]}\\n")
    response = {}
else:
    print(f"Unexpected fake AWS operation: {operation}", file=sys.stderr)
    sys.exit(2)

print(json.dumps(response))
"""


def cleanup_scenario(module_id=INSTANCE_ID, account_id=ACCOUNT_ID):
    return {
        "identity": {"Account": account_id},
        "images": {
            "imageVersionList": [
                {"arn": IMAGE_VERSION_1},
                {"arn": IMAGE_VERSION_2},
            ]
        },
        "image_build_versions": {
            IMAGE_VERSION_1: {
                "imageSummaryList": [
                    {
                        "arn": IMAGE_BUILD_1,
                        "tags": {"ModuleId": module_id},
                        "state": {"status": "AVAILABLE"},
                    },
                    {
                        "arn": IMAGE_BUILD_EXTERNAL,
                        "tags": {"ModuleId": "another-module"},
                        "state": {"status": "BUILDING"},
                    },
                ]
            },
            IMAGE_VERSION_2: {
                "imageSummaryList": [
                    {
                        "arn": IMAGE_BUILD_2,
                        "tags": {"ModuleId": module_id},
                        "state": {"status": "FAILED"},
                    }
                ]
            },
        },
        "recipes": {
            "imageRecipeSummaryList": [
                {"arn": RECIPE_1, "tags": {"ModuleId": module_id}},
                {"arn": RECIPE_2, "tags": {"ModuleId": module_id}},
                {"arn": RECIPE_EXTERNAL, "tags": {"ModuleId": "another-module"}},
            ]
        },
        "components": {
            "componentVersionList": [
                {"arn": COMPONENT_VERSION_1},
                {"arn": COMPONENT_VERSION_2},
                {"arn": COMPONENT_VERSION_EXTERNAL},
            ]
        },
        "component_build_versions": {
            COMPONENT_VERSION_1: {
                "componentSummaryList": [
                    {
                        "arn": COMPONENT_VERSION_1,
                        "tags": {
                            "ModuleId": module_id,
                            "Module": "compute/ami",
                            "ManagedBy": "terraform",
                        },
                    }
                ]
            },
            COMPONENT_VERSION_2: {
                "componentSummaryList": [
                    {
                        "arn": COMPONENT_VERSION_2,
                        "tags": {
                            "ModuleId": module_id,
                            "Module": "compute/ami",
                            "ManagedBy": "terraform",
                        },
                    }
                ]
            },
            COMPONENT_VERSION_EXTERNAL: {
                "componentSummaryList": [
                    {
                        "arn": COMPONENT_VERSION_EXTERNAL,
                        "tags": {
                            "ModuleId": module_id,
                            "Module": "compute/ami",
                            "ManagedBy": "external",
                        },
                    }
                ]
            },
        },
        "failures": {},
    }


class FakeAwsTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_dir = Path(self.temp_dir.name)
        self.bin_dir = self.test_dir / "bin"
        self.bin_dir.mkdir()
        self.fake_aws_path = self.bin_dir / "aws"
        self.fake_aws_path.write_text(FAKE_AWS, encoding="utf-8")
        self.fake_aws_path.chmod(0o755)
        self.scenario_path = self.test_dir / "scenario.json"
        self.aws_log_path = self.test_dir / "aws.jsonl"
        self.trace_path = self.test_dir / "trace.log"

    def tearDown(self):
        self.temp_dir.cleanup()

    def write_scenario(self, scenario):
        self.scenario_path.write_text(json.dumps(scenario), encoding="utf-8")
        self.aws_log_path.unlink(missing_ok=True)
        self.trace_path.unlink(missing_ok=True)

    def make_test_environment(self):
        environment = os.environ.copy()
        for name in list(environment):
            if name.startswith("AWS_"):
                environment.pop(name)
        environment.update(
            {
                "PATH": f"{self.bin_dir}{os.pathsep}{environment['PATH']}",
                "FAKE_AWS_SCENARIO": str(self.scenario_path),
                "FAKE_AWS_LOG": str(self.aws_log_path),
                "CLEANUP_TRACE": str(self.trace_path),
            }
        )
        return environment

    def aws_calls(self):
        if not self.aws_log_path.exists():
            return []
        return [
            json.loads(line)
            for line in self.aws_log_path.read_text(encoding="utf-8").splitlines()
        ]

    def run_cleanup(self, scenario, module_id=INSTANCE_ID, include_identity=True):
        self.write_scenario(scenario)
        environment = self.make_test_environment()
        environment["MODULE_INSTANCE_ID"] = module_id
        if include_identity:
            environment["AWS_REGION"] = "us-west-2"
            environment["AWS_ACCOUNT_ID"] = ACCOUNT_ID
        return subprocess.run(
            ["bash", str(CLEANUP_SCRIPT)],
            env=environment,
            capture_output=True,
            check=False,
            text=True,
        )


class CleanupScriptTests(FakeAwsTestCase):
    def test_deletes_only_owned_resources_in_dependency_order(self):
        result = self.run_cleanup(cleanup_scenario())
        self.assertEqual(result.returncode, 0, result.stderr)

        calls = self.aws_calls()
        delete_calls = [
            call
            for call in calls
            if call[0] == "imagebuilder" and call[1].startswith("delete-")
        ]
        self.assertEqual(
            [call[1] for call in delete_calls],
            [
                "delete-image",
                "delete-image",
                "delete-image-recipe",
                "delete-image-recipe",
                "delete-component",
                "delete-component",
            ],
        )
        self.assertEqual(
            [call[call.index("--image-build-version-arn") + 1] for call in delete_calls[:2]],
            [IMAGE_BUILD_1, IMAGE_BUILD_2],
        )
        self.assertEqual(
            [call[call.index("--image-recipe-arn") + 1] for call in delete_calls[2:4]],
            [RECIPE_1, RECIPE_2],
        )
        self.assertEqual(
            [
                call[call.index("--component-build-version-arn") + 1]
                for call in delete_calls[4:]
            ],
            [COMPONENT_VERSION_1, COMPONENT_VERSION_2],
        )

        first_delete = calls.index(delete_calls[0])
        discovery_calls = [
            index
            for index, call in enumerate(calls)
            if call[0] == "imagebuilder" and call[1].startswith("list-")
        ]
        self.assertTrue(discovery_calls)
        self.assertLess(max(discovery_calls), first_delete)
        self.assertTrue(all(call[0] != "ec2" for call in calls))

    def test_active_owned_build_stops_before_deletion(self):
        scenario = cleanup_scenario()
        scenario["image_build_versions"][IMAGE_VERSION_1]["imageSummaryList"][0][
            "state"
        ]["status"] = "BUILDING"

        result = self.run_cleanup(scenario)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("active or has an unknown status", result.stderr)
        self.assertFalse(any(call[1].startswith("delete-") for call in self.aws_calls()))

    def test_account_mismatch_stops_before_discovery_or_deletion(self):
        result = self.run_cleanup(cleanup_scenario(account_id="999999999999"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match state account", result.stderr)
        self.assertEqual(
            self.aws_calls(),
            [
                [
                    "sts",
                    "get-caller-identity",
                    "--region",
                    "us-west-2",
                    "--output",
                    "json",
                ]
            ],
        )

    def test_discovery_failure_stops_before_deletion(self):
        scenario = cleanup_scenario()
        scenario["failures"]["imagebuilder list-image-recipes"] = "AccessDeniedException"

        result = self.run_cleanup(scenario)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[1].startswith("delete-") for call in self.aws_calls()))

    def test_not_found_is_tolerated(self):
        scenario = cleanup_scenario()
        scenario["failures"]["imagebuilder delete-image"] = "ResourceNotFoundException"

        result = self.run_cleanup(scenario)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("delete-image-recipe", [call[1] for call in self.aws_calls()])

    def test_dependency_failure_stops_subsequent_deletions(self):
        scenario = cleanup_scenario()
        scenario["failures"]["imagebuilder delete-image-recipe"] = (
            "ResourceDependencyException"
        )

        result = self.run_cleanup(scenario)
        self.assertNotEqual(result.returncode, 0)
        delete_operations = [
            call[1]
            for call in self.aws_calls()
            if call[0] == "imagebuilder" and call[1].startswith("delete-")
        ]
        self.assertEqual(
            delete_operations,
            ["delete-image", "delete-image", "delete-image-recipe"],
        )

    def test_unset_module_id_skips_all_aws_calls(self):
        result = self.run_cleanup(
            cleanup_scenario(), module_id="", include_identity=False
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No module_instance_id", result.stdout)
        self.assertEqual(self.aws_calls(), [])


@unittest.skipUnless(TOFU_BIN, "OpenTofu is required for the lifecycle test")
class TerraformCleanupLifecycleTests(FakeAwsTestCase):
    def tofu(self, module_dir, *args, environment):
        return subprocess.run(
            [TOFU_BIN, *args],
            cwd=module_dir,
            env=environment,
            capture_output=True,
            check=False,
            text=True,
            timeout=120,
        )

    def state_resources(self, module_dir, environment):
        result = self.tofu(module_dir, "show", "-json", environment=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = json.loads(result.stdout)["values"]["root_module"]["resources"]
        return {resource["address"]: resource["values"] for resource in resources}

    def test_component_replacement_preserves_hook_until_destroy(self):
        module_id = "ami-instance-lifecycle"
        self.write_scenario(cleanup_scenario(module_id=module_id))
        module_dir = self.test_dir / "terraform"
        module_dir.mkdir()
        shutil.copy2(CLEANUP_SCRIPT, module_dir / CLEANUP_SCRIPT.name)

        cleanup_hcl = BUILD_CLEANUP_TF.read_text(encoding="utf-8")
        substitutions = {
            "aws_imagebuilder_component.this": 'terraform_data.component',
            "aws_imagebuilder_infrastructure_configuration.this": (
                "terraform_data.infrastructure"
            ),
            "aws_imagebuilder_distribution_configuration.this": (
                "terraform_data.distribution"
            ),
            "local.region": '"us-west-2"',
            "data.aws_caller_identity.current.account_id": f'"{ACCOUNT_ID}"',
            'var.module_instance_id == null ? "" : var.module_instance_id': (
                f'"{module_id}"'
            ),
        }
        for original, replacement in substitutions.items():
            self.assertEqual(cleanup_hcl.count(original), 1)
            cleanup_hcl = cleanup_hcl.replace(original, replacement)

        stand_ins = textwrap.dedent(
            """
            terraform {
              required_version = ">= 1.10.0"
            }

            variable "component_content" {
              type = string
            }

            resource "terraform_data" "component" {
              input           = var.component_content
              triggers_replace = [var.component_content]

              lifecycle {
                create_before_destroy = true
              }
            }

            resource "terraform_data" "infrastructure" {
              input = "infrastructure"

              provisioner "local-exec" {
                when        = destroy
                command     = "printf 'infrastructure-destroy\\\\n' >> \\"$CLEANUP_TRACE\\""
                environment = { CLEANUP_TRACE = "${path.module}/trace.log" }
              }
            }

            resource "terraform_data" "distribution" {
              input = "distribution"

              provisioner "local-exec" {
                when        = destroy
                command     = "printf 'distribution-destroy\\\\n' >> \\"$CLEANUP_TRACE\\""
                environment = { CLEANUP_TRACE = "${path.module}/trace.log" }
              }
            }
            """
        )
        (module_dir / "main.tf").write_text(
            stand_ins + "\n" + cleanup_hcl, encoding="utf-8"
        )
        environment = self.make_test_environment()
        environment["CLEANUP_TRACE"] = str(module_dir / "trace.log")

        init = self.tofu(
            module_dir,
            "init",
            "-backend=false",
            "-input=false",
            "-no-color",
            environment=environment,
        )
        self.assertEqual(init.returncode, 0, init.stdout + init.stderr)

        initial_apply = self.tofu(
            module_dir,
            "apply",
            "-auto-approve",
            "-input=false",
            "-no-color",
            "-var",
            "component_content=initial",
            environment=environment,
        )
        self.assertEqual(
            initial_apply.returncode, 0, initial_apply.stdout + initial_apply.stderr
        )
        self.assertEqual(self.aws_calls(), [])
        initial_resources = self.state_resources(module_dir, environment)
        initial_hook = initial_resources["terraform_data.build_cleanup"]
        cleanup_id = initial_hook["id"]
        component_id = initial_resources["terraform_data.component"]["id"]
        self.assertEqual(initial_hook["input"]["region"], "us-west-2")
        self.assertEqual(initial_hook["input"]["account_id"], ACCOUNT_ID)
        self.assertEqual(initial_hook["input"]["module_instance_id"], module_id)
        self.assertEqual(
            initial_hook["input"]["script"],
            CLEANUP_SCRIPT.read_text(encoding="utf-8"),
        )

        update_apply = self.tofu(
            module_dir,
            "apply",
            "-auto-approve",
            "-input=false",
            "-no-color",
            "-var",
            "component_content=updated",
            environment=environment,
        )
        self.assertEqual(
            update_apply.returncode, 0, update_apply.stdout + update_apply.stderr
        )
        updated_resources = self.state_resources(module_dir, environment)
        self.assertEqual(updated_resources["terraform_data.build_cleanup"]["id"], cleanup_id)
        self.assertNotEqual(updated_resources["terraform_data.component"]["id"], component_id)
        self.assertEqual(self.aws_calls(), [])

        destroy = self.tofu(
            module_dir,
            "destroy",
            "-auto-approve",
            "-input=false",
            "-no-color",
            "-var",
            "component_content=updated",
            environment=environment,
        )
        self.assertEqual(destroy.returncode, 0, destroy.stdout + destroy.stderr)

        calls = self.aws_calls()
        delete_calls = [
            call
            for call in calls
            if call[0] == "imagebuilder" and call[1].startswith("delete-")
        ]
        self.assertEqual(
            [call[1] for call in delete_calls],
            [
                "delete-image",
                "delete-image",
                "delete-image-recipe",
                "delete-image-recipe",
                "delete-component",
                "delete-component",
            ],
        )
        trace = (module_dir / "trace.log").read_text(encoding="utf-8").splitlines()
        deletion_positions = [
            index for index, line in enumerate(trace) if line.startswith("delete:")
        ]
        stand_in_positions = [
            index
            for index, line in enumerate(trace)
            if line in {"infrastructure-destroy", "distribution-destroy"}
        ]
        self.assertTrue(deletion_positions)
        self.assertEqual(len(stand_in_positions), 2)
        self.assertLess(max(deletion_positions), min(stand_in_positions))


if __name__ == "__main__":
    unittest.main()
