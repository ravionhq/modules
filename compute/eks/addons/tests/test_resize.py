"""Offline regression tests for the resizer's record boundaries and ordinals."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "charts/ebs-storage/files/resize.sh"


class ResizeTests(unittest.TestCase):
    def run_pass(self, statefulsets, claims):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            kubectl = root / "kubectl"
            kubectl.write_text("""#!/bin/sh
if [ "$1" = get ]; then
  if [ "$2" = statefulsets ]; then
    printf '%s' "$STATEFULSETS"
  else
    printf '%s' "$CLAIMS"
  fi
elif [ "$1" = patch ]; then
  printf '%s\\n' "$*" >> "$PATCHES"
else
  exit 1
fi
""")
            kubectl.chmod(0o755)
            # Stop the infinite resizer loop after the first pass.
            sleep = root / "sleep"
            sleep.write_text('#!/bin/sh\nkill -TERM "$PPID"\n')
            sleep.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       SIZES_ANNOTATION="ravion.com/volume-claim-template-sizes",
                       STATEFULSETS=statefulsets, CLAIMS=claims,
                       PATCHES=str(root / "patches"), TMPDIR=tmp)
            result = subprocess.run(["sh", str(SCRIPT)], env=env,
                                    capture_output=True, text=True, timeout=5)
            self.assertIn("resizer started", result.stdout)
            self.assertNotIn("pass failed", result.stdout)
            patches = root / "patches"
            return patches.read_text().splitlines() if patches.exists() else []

    def test_nonzero_start_ordinal(self):
        patches = self.run_pass(
            'team database 2 3 "data=20Gi"\n',
            'team data-database-0 Bound 10Gi\n'
            'team data-database-3 Bound 10Gi\n'
            'team data-database-4 Bound 10Gi\n',
        )
        self.assertEqual(len(patches), 2)
        self.assertIn('data-database-3', patches[0])
        self.assertIn('data-database-4', patches[1])
        self.assertTrue(all('database-0' not in patch for patch in patches))

    def test_forged_newline_cannot_patch_other_namespace(self):
        # Go's printf %q escapes embedded newlines before producing a record.
        patches = self.run_pass(
            'team database 1 0 "data=20Gi\\nother target 1 0 data=50Gi"\n',
            'other data-target-0 Bound 10Gi\n',
        )
        self.assertEqual(patches, [])

    def test_legacy_unquoted_forged_record_is_rejected(self):
        patches = self.run_pass(
            'team database 1 0 "data=20Gi"\nother target 1 0 data=50Gi\n',
            'other data-target-0 Bound 10Gi\n',
        )
        self.assertEqual(patches, [])

    def test_malformed_size_is_not_used_in_patch(self):
        patches = self.run_pass(
            'team database 1 0 "data=20GiX"\n',
            'team data-database-0 Bound 10Gi\n',
        )
        self.assertEqual(patches, [])


if __name__ == "__main__":
    unittest.main()
