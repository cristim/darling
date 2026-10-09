import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent / "lock_diff.py"
A, B, C = "a" * 40, "b" * 40, "c" * 40


def top(darling, kernel):
    return {"repos": [{"repo": "darling", "branch": "master", "base": darling, "prs": []},
                      {"repo": "darling-xnu", "branch": "main", "base": kernel, "prs": []}]}


def nested(core, pin):
    return {"vibedarling": [{"repo": "darling-core", "branch": "main", "base": core, "prs": []}],
            "external_pinned": [{"repo": "zlib", "pin": pin}]}


class Diff(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, refs, nest):
        d = self.root / name
        d.mkdir(exist_ok=True)
        (d / "refs.lock.json").write_text(json.dumps(refs))
        (d / "nested.refs.lock.json").write_text(json.dumps(nest))

    def run_diff(self, old, force=False):
        out = self.root / "gh-output"
        md = self.root / "changes.md"
        cmd = [sys.executable, str(HELPER), "diff", "--old", str(self.root / old), "--new", str(self.root / "new"),
               "--markdown", str(md), "--github-output", str(out)] + (["--force"] if force else [])
        subprocess.run(cmd, check=True, capture_output=True)
        return out.read_text().strip(), md.read_text()

    def test_unchanged_skips(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(A, B))
        self.assertEqual(self.run_diff("old")[0], "build=false")

    def test_unchanged_force_builds(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(A, B))
        self.assertEqual(self.run_diff("old", force=True)[0], "build=true")

    def test_superproject_change(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(C, B), nested(A, B))
        build, md = self.run_diff("old")
        self.assertEqual(build, "build=true")
        self.assertIn(f"| darling | master | {A[:12]} | {C[:12]} |", md)
        self.assertNotIn("darling-xnu", md)

    def test_nested_and_pin_change(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(C, C))
        build, md = self.run_diff("old")
        self.assertEqual(build, "build=true")
        self.assertIn(f"| darling-core | main | {A[:12]} | {C[:12]} |", md)
        self.assertIn(f"| zlib |  | {B[:12]} | {C[:12]} |", md)

    def test_first_run_builds(self):
        self.write("new", top(A, B), nested(A, B))
        build, md = self.run_diff("missing")
        self.assertEqual(build, "build=true")
        self.assertIn("first build", md)

    def test_new_module_listed(self):
        self.write("old", top(A, B), nested(A, B))
        grown = top(A, B)
        grown["repos"].append({"repo": "darling-new", "branch": "main", "base": C, "prs": []})
        self.write("new", grown, nested(A, B))
        self.assertIn(f"| darling-new | main | (none) | {C[:12]} |", self.run_diff("old")[1])

    def test_refresh_nested_updates_branch_heads_only(self):
        builder = self.root / "builder.py"
        builder.write_text(f"def remote_refs(item):\n    item['base'] = {C!r}\n    return item\n")
        (self.root / "old.json").write_text(json.dumps(nested(A, B)))
        subprocess.run([sys.executable, str(HELPER), "refresh-nested", "--builder", str(builder),
                        "--lock", str(self.root / "old.json"), "--output", str(self.root / "cur.json")], check=True)
        lock = json.loads((self.root / "cur.json").read_text())
        self.assertEqual(lock["vibedarling"][0]["base"], C)
        self.assertEqual(lock["external_pinned"], nested(A, B)["external_pinned"])


if __name__ == "__main__":
    unittest.main()
