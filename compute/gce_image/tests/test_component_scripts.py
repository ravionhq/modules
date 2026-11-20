"""Runs the component scripts the module writes, as a build would.

The module renders each component into one bash script with every step
embedded base64-encoded. These tests render real scripts with OpenTofu and
run them, so quoting, parameters, failure handling and timeouts are checked
by bash itself rather than by reading the template.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE_DIR = Path(__file__).resolve().parents[1]
TOFU_BIN = os.environ.get("TOFU_BIN") or shutil.which("tofu")
TIMEOUT_BIN = shutil.which("timeout")

# A default that would break any naive quoting: both quote kinds, a command
# substitution, a variable, a backslash and a newline.
TRICKY_DEFAULT = "it's \"$HOME\" $(echo injected) `echo backtick` \\n\nsecond line"

COMPONENTS = [
    {
        "name": "app",
        "description": "Installs the app",
        "parameter_definitions": [
            {"name": "Greeting", "default": TRICKY_DEFAULT},
            {"name": "Version", "default": "v1"},
            {"name": "Required"},
        ],
        "build_steps": [
            {
                "name": "First",
                "commands": [
                    'printf "%s" "$Greeting" > "$OUT/greeting"',
                    'echo "$Version" > "$OUT/version"',
                    "echo first >> \"$OUT/order\"",
                ],
            },
            {
                "name": "ReadsStdin",
                # With stdin closed, cat sees end of file at once instead of
                # reading the rest of the script.
                "commands": ["cat > \"$OUT/stdin\"", "echo stdin >> \"$OUT/order\""],
            },
            {
                "name": "Multiline",
                "commands": [
                    "cat > \"$OUT/heredoc\" <<'EOF'\nline 'one'\n\"two\" $NOT_EXPANDED\nEOF",
                    "echo multiline >> \"$OUT/order\"",
                ],
            },
        ],
        "test_steps": [{"name": "UsesRequired", "commands": ['echo "$Required" > "$OUT/required"']}],
    },
    {
        "name": "failing",
        "build_steps": [
            {"name": "Ok", "commands": ["echo ok >> \"$OUT/order\""]},
            {"name": "Boom", "commands": ["echo before >> \"$OUT/order\"", "exit 7", "echo after >> \"$OUT/order\""]},
            {"name": "Never", "commands": ["echo never >> \"$OUT/order\""]},
        ],
        "validate_steps": [
            {"name": "PipeFails", "commands": ["false | true", "echo unreachable >> \"$OUT/order\""]},
        ],
        "test_steps": [{"name": "Slow", "commands": ["sleep 30"], "timeout_seconds": 1}],
    },
]


def render_scripts():
    """The module's component scripts for COMPONENTS, keyed by name."""
    work = Path(tempfile.mkdtemp(prefix="gce-image-render-"))
    try:
        for tf in MODULE_DIR.glob("*.tf"):
            text = tf.read_text()
            if tf.name == "versions.tf":
                # The Ravion state backend is set at run time; rendering needs none.
                text = text.replace("cloud {}", "")
            (work / tf.name).write_text(text)
        lock = MODULE_DIR / ".terraform.lock.hcl"
        if lock.exists():
            shutil.copy(lock, work / lock.name)
        variables = {
            "name": "app-image",
            "project_id": "acme-images-1",
            "region": "us-central1",
            "components": COMPONENTS,
        }
        (work / "test.tfvars.json").write_text(json.dumps(variables))
        subprocess.run(
            [TOFU_BIN, "init", "-backend=false", "-input=false", "-no-color"],
            cwd=work, check=True, capture_output=True, text=True,
        )
        console = subprocess.run(
            [TOFU_BIN, "console", "-var-file=test.tfvars.json", "-no-color"],
            cwd=work, input="jsonencode(local.component_scripts)\n",
            check=True, capture_output=True, text=True,
        )
        return json.loads(json.loads(console.stdout.strip()))
    finally:
        shutil.rmtree(work, ignore_errors=True)


@unittest.skipUnless(TOFU_BIN, "OpenTofu is required to render the component scripts")
class ComponentScriptTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scripts = render_scripts()

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="gce-image-run-"))
        self.out = self.dir / "out"
        self.out.mkdir()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_phase(self, component, phase, env=None):
        script = self.dir / f"{component}.sh"
        script.write_text(self.scripts[component])
        run_env = {"PATH": os.environ["PATH"], "HOME": "/nonexistent-home", "OUT": str(self.out)}
        run_env.update(env or {})
        return subprocess.run(
            ["bash", str(script), phase], env=run_env, capture_output=True, text=True, timeout=60,
        )

    def read(self, name):
        return (self.out / name).read_text()

    def test_build_runs_every_step_in_order_with_defaults(self):
        result = self.run_phase("app", "build")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read("greeting"), TRICKY_DEFAULT)
        self.assertEqual(self.read("version"), "v1\n")
        self.assertEqual(self.read("order").split(), ["first", "stdin", "multiline"])
        self.assertEqual(self.read("stdin"), "")
        self.assertEqual(self.read("heredoc"), "line 'one'\n\"two\" $NOT_EXPANDED\n")
        self.assertIn("gce-image: build step First started", result.stdout)
        self.assertIn("gce-image: build step Multiline started", result.stdout)

    def test_the_environment_overrides_a_default(self):
        result = self.run_phase("app", "build", {"Version": "v2", "Greeting": ""})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read("version"), "v2\n")
        # Set to empty is set: the default applies only when unset.
        self.assertEqual(self.read("greeting"), "")

    def test_a_parameter_without_default_or_value_fails_the_step_that_reads_it(self):
        result = self.run_phase("app", "test")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("gce-image: test step UsesRequired failed with exit", result.stdout)
        result = self.run_phase("app", "test", {"Required": "given"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read("required"), "given\n")

    def test_a_phase_without_steps_succeeds(self):
        result = self.run_phase("app", "validate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_the_first_failing_command_stops_the_phase_with_its_code(self):
        result = self.run_phase("failing", "build")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.read("order").split(), ["ok", "before"])
        self.assertIn("gce-image: build step Boom failed with exit 7", result.stdout)
        self.assertNotIn("Never", result.stdout)

    def test_a_failing_pipeline_fails_the_step(self):
        result = self.run_phase("failing", "validate")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.out / "order").exists())

    @unittest.skipUnless(TIMEOUT_BIN, "coreutils timeout is required")
    def test_a_step_past_its_timeout_is_stopped(self):
        result = self.run_phase("failing", "test")
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
        self.assertIn("gce-image: test step Slow failed with exit 124", result.stdout)

    def test_an_unknown_phase_is_refused(self):
        for phase in ["", "deploy"]:
            result = self.run_phase("app", phase)
            self.assertEqual(result.returncode, 2)
            self.assertIn("usage:", result.stderr)

    def test_the_script_names_the_component(self):
        self.assertIn("# Component app, written by the gce_image module.\n# Installs the app\n", self.scripts["app"])


if __name__ == "__main__":
    unittest.main()
