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

    def write(self, name, refs, nest, recipe="r1"):
        d = self.root / name
        d.mkdir(exist_ok=True)
        if name == "old":
            (d / "manifest.json").write_text(json.dumps(
                {"build": {"recipe_sha256": recipe}}))
        (d / "refs.lock.json").write_text(json.dumps(refs))
        (d / "nested.refs.lock.json").write_text(json.dumps(nest))

    def run_diff(self, old, force=False):
        out = self.root / "gh-output"
        md = self.root / "changes.md"
        cmd = [sys.executable, str(HELPER), "diff", "--old", str(self.root / old), "--new", str(self.root / "new"),
               "--markdown", str(md), "--github-output", str(out), "--recipe", "r1"] + (["--force"] if force else [])
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

    def test_recipe_change_builds(self):
        self.write("old", top(A, B), nested(A, B), recipe="other")
        self.write("new", top(A, B), nested(A, B))
        build, md = self.run_diff("old")
        self.assertEqual(build, "build=true")
        self.assertIn("recipe", md)

    def test_old_release_without_recipe_builds(self):
        self.write("old", top(A, B), nested(A, B))
        (self.root / "old" / "manifest.json").write_text(json.dumps({"artifacts": {"aarch64": {}, "x86_64": {}}}))
        self.write("new", top(A, B), nested(A, B))
        self.assertEqual(self.run_diff("old")[0], "build=true")

    def run_raw(self, force=False):
        cmd = [sys.executable, str(HELPER), "diff", "--old", str(self.root / "old"), "--new", str(self.root / "new"),
               "--markdown", str(self.root / "c.md"), "--github-output", str(self.root / "o"), "--recipe", "r1"]
        return subprocess.run(cmd + (["--force"] if force else []), capture_output=True, text=True)

    def test_malformed_previous_lock_fails_clearly(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(A, B))
        (self.root / "old" / "refs.lock.json").write_text("{not json")
        got = self.run_raw()
        self.assertNotEqual(got.returncode, 0)
        self.assertIn("is not a valid builder lock", got.stderr)
        self.assertNotIn("Traceback", got.stderr)

    def test_wrong_shape_previous_lock_fails_clearly(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(A, B))
        (self.root / "old" / "nested.refs.lock.json").write_text('{"x": 1}')
        got = self.run_raw()
        self.assertIn("is not a valid builder lock", got.stderr)
        self.assertNotIn("Traceback", got.stderr)

    def test_force_ignores_malformed_previous_lock(self):
        self.write("old", top(A, B), nested(A, B))
        self.write("new", top(A, B), nested(A, B))
        (self.root / "old" / "refs.lock.json").write_text("{not json")
        self.assertEqual(self.run_raw(force=True).returncode, 0)
        self.assertEqual((self.root / "o").read_text().strip(), "build=true")

    def test_refresh_nested_updates_branch_heads_only(self):
        builder = self.root / "builder.py"
        builder.write_text(f"def remote_refs(item):\n    item['base'] = {C!r}\n    return item\n")
        (self.root / "old.json").write_text(json.dumps(nested(A, B)))
        subprocess.run([sys.executable, str(HELPER), "refresh-nested", "--builder", str(builder),
                        "--lock", str(self.root / "old.json"), "--output", str(self.root / "cur.json")], check=True)
        lock = json.loads((self.root / "cur.json").read_text())
        self.assertEqual(lock["vibedarling"][0]["base"], C)
        self.assertEqual(lock["external_pinned"], nested(A, B)["external_pinned"])


def release(tag, created, draft=False, prerelease=False, assets=("refs.lock.json", "nested.refs.lock.json", "manifest.json")):
    return {"tag_name": tag, "draft": draft, "prerelease": prerelease, "created_at": created, "assets": [{"name": a} for a in assets]}


class Select(unittest.TestCase):
    def pick(self, releases):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "releases.json")
            path.write_text(json.dumps(releases))
            return subprocess.run([sys.executable, str(HELPER), "select-release", "--releases", str(path)],
                                  check=True, capture_output=True, text=True).stdout.strip()

    def test_skips_changelog_releases(self):
        got = self.pick([release("v0.1.20260921", "2026-09-21", assets=()),
                         release("v2026.10.08-abcdef1", "2026-10-08")])
        self.assertEqual(got, "v2026.10.08-abcdef1")

    def test_skips_drafts_and_releases_missing_assets(self):
        got = self.pick([release("v2026.10.09-abcdef1", "2026-10-09", draft=True),
                         release("v2026.10.08-abcdef1", "2026-10-08", assets=("refs.lock.json",)),
                         release("v2026.10.07-abcdef1", "2026-10-07")])
        self.assertEqual(got, "v2026.10.07-abcdef1")

    def test_skips_prereleases(self):
        got = self.pick([release("v2026.10.09-abcdef1", "2026-10-09", prerelease=True),
                         release("v2026.10.08-abcdef1", "2026-10-08")])
        self.assertEqual(got, "v2026.10.08-abcdef1")

    def test_newest_wins_and_rebuild_suffix_accepted(self):
        got = self.pick([release("v2026.10.09-abcdef1", "2026-10-09T01:00:00Z"),
                         release("v2026.10.09-abcdef1-r2", "2026-10-09T05:00:00Z")])
        self.assertEqual(got, "v2026.10.09-abcdef1-r2")

    def test_none_is_empty(self):
        self.assertEqual(self.pick([release("v0.1.20260921", "2026-09-21")]), "")
        self.assertEqual(self.pick([]), "")


class Recipe(unittest.TestCase):
    def test_hash_depends_on_content_and_extra(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp, "w.yml")
            f.write_text("a")
            def run(extra):
                return subprocess.run([sys.executable, str(HELPER), "recipe", f"--extra={extra}", str(f)],
                                      check=True, capture_output=True, text=True).stdout
            first = run("")
            self.assertEqual(first, run(""))
            self.assertNotEqual(first, run("-DX=1"))
            f.write_text("b")
            self.assertNotEqual(first, run(""))


if __name__ == "__main__":
    unittest.main()
