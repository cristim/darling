import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/release-binaries.yml"


class ReleaseKind(unittest.TestCase):
    def test_actual_workflow_fragment_matrix(self):
        step = WORKFLOW.read_text().split("      - name: Decide the release kind\n", 1)[1]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0])
        for count in (0, 1, 2):
            for partial in ("", "false", "true"):
                for pre in ("false", "true"):
                    with self.subTest(count=count, partial=partial, pre=pre):
                        with tempfile.TemporaryDirectory() as root:
                            root = Path(root)
                            for arch in ("aarch64", "x86_64")[:count]:
                                directory = root / "art" / f"runtime-{arch}"
                                directory.mkdir(parents=True)
                                (directory / f"fragment-{arch}.json").write_text("{}")
                            output = root / "output"
                            env = dict(os.environ, ALLOW_PARTIAL=partial, PRERELEASE=pre,
                                       GITHUB_OUTPUT=str(output))
                            done = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script],
                                                  cwd=root, env=env, capture_output=True, text=True)
                            allowed = count == 2 or (count == 1 and partial == "true")
                            self.assertEqual(done.returncode == 0, allowed, done.stderr)
                            if allowed:
                                expected = "--prerelease" if count == 1 or pre == "true" else ""
                                self.assertEqual(output.read_text(), f"flag={expected}\n")
                            else:
                                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
