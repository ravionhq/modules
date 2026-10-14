"""Check every Helm release of a chart in this module pins its Chart.yaml version.

The Helm provider does not read a local chart's version at plan time. A
release without a pinned version plans the old version after a Chart.yaml
bump, and the apply then fails with "Provider produced inconsistent result".

Run from the add-ons module:
    python3 -B -m unittest discover -s tests -p 'test_local_chart_versions.py'
"""

from pathlib import Path
import re
import unittest

MODULE = Path(__file__).resolve().parents[1]
RELEASE = re.compile(r'^resource\s+"helm_release"\s+"([^"]+)"\s*\{(.*?)^\}', re.M | re.S)
LOCAL_CHART = re.compile(r'^\s*chart\s*=\s*"\$\{path\.module\}/charts/([^"/]+)"', re.M)


class LocalChartVersionsTest(unittest.TestCase):
    def test_every_local_chart_release_pins_its_chart_version(self):
        checked = 0
        for source in sorted(MODULE.glob("*.tf")):
            for name, body in RELEASE.findall(source.read_text()):
                chart = LOCAL_CHART.search(body)
                if not chart:
                    continue
                checked += 1
                pin = f'version = yamldecode(file("${{path.module}}/charts/{chart.group(1)}/Chart.yaml")).version'
                with self.subTest(release=name, file=source.name):
                    self.assertTrue((MODULE / "charts" / chart.group(1) / "Chart.yaml").is_file())
                    self.assertIn(pin, re.sub(r"[ \t]+=", " =", body))
        self.assertGreater(checked, 0, "no local chart releases found; the pattern is stale")


if __name__ == "__main__":
    unittest.main()
