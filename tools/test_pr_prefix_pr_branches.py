import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "builder", Path(__file__).parent / "all-vibedarling-pr-prefix.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

BASE, HEAD = "a" * 40, "b" * 40


def fake_git(*args, **kwargs):
    if args[:3] == ("git", "remote", "get-url"):
        return b.ROOT
    if args[:2] == ("git", "status"):
        return ""
    if args[:3] == ("git", "ls-remote", "--symref"):
        lines = ["ref: refs/heads/main\tHEAD", f"{BASE}\tHEAD", f"{BASE}\trefs/heads/main"]
        lines += [f"{HEAD if p.startswith('refs/pull/') else BASE}\t{p}" for p in args[4:]
                  if p not in ("HEAD", "refs/heads/main", "refs/heads/master")]
        return "\n".join(lines)
    return BASE


def pull(number, repo):
    return {"number": number, "repository_url": f"https://api.github.com/repos/VibeDarling/{repo}",
            "html_url": f"https://github.com/VibeDarling/{repo}/pull/{number}", "title": f"pr {number}"}


class BaseBranchTests(unittest.TestCase):
    def resolve(self, modules, prs, bases):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "refs.lock.json"
            args = SimpleNamespace(source=tmp, output=str(out), repo=None, jobs=1, no_prs=False)
            with patch.object(b, "run", side_effect=fake_git), \
                    patch.object(b, "modules", return_value=modules), \
                    patch.object(b, "open_prs", return_value=prs), \
                    patch.object(b, "api", side_effect=lambda path: {
                        "base": {"ref": bases[int(path.rsplit("/", 1)[-1])]}}):
                b.resolve(args)
            return json.loads(out.read_text())

    def entry(self, repo, **extra):
        return {"repo": repo, "paths": [f"src/external/{repo}"],
                "url": f"https://github.com/VibeDarling/{repo}.git", "kind": "VibeDarling", **extra}

    def test_pr_to_a_non_default_branch_is_excluded_not_merged(self):
        lock = self.resolve([self.entry("cocotron")],
                            [pull(7, "cocotron"), pull(8, "cocotron")], {7: "release", 8: "main"})
        by_repo = {i["repo"]: i for i in lock["repos"]}
        self.assertEqual([p["number"] for p in by_repo["cocotron"]["prs"]], [8])
        self.assertEqual([(e["number"], e["repo"]) for e in lock["excluded_open_prs"]], [(7, "cocotron")])
        self.assertIn("targets release, not the locked branch main", lock["excluded_open_prs"][0]["reason"])
        self.assertNotIn("off_branch_prs", by_repo["cocotron"])

    def test_untracked_libressl_branch_excludes_only_that_pr(self):
        libressl = [self.entry("libressl", requested_branch="v2.8.3"),
                    self.entry("libressl", requested_branch="v2.6.5")]
        lock = self.resolve(libressl, [pull(3, "libressl"), pull(4, "libressl")], {3: "master", 4: "v2.6.5"})
        attached = {i["requested_branch"]: [p["number"] for p in i["prs"]]
                    for i in lock["repos"] if i["repo"] == "libressl"}
        self.assertEqual(attached, {"v2.8.3": [], "v2.6.5": [4]})
        self.assertEqual([(e["number"], e["reason"]) for e in lock["excluded_open_prs"]],
                         [(3, "targets untracked branch master")])

    def test_repo_filter_skips_the_base_lookup_for_other_repositories(self):
        looked_up = []

        def api(path):
            looked_up.append(path)
            return {"base": {"ref": "main"}}
        with tempfile.TemporaryDirectory() as tmp:
            args = SimpleNamespace(source=tmp, output=str(Path(tmp) / "lock.json"), repo=["cocotron"],
                                   jobs=1, no_prs=False)
            with patch.object(b, "run", side_effect=fake_git), \
                    patch.object(b, "modules", return_value=[self.entry("cocotron"), self.entry("xnu")]), \
                    patch.object(b, "open_prs", return_value=[pull(1, "cocotron"), pull(2, "xnu"), pull(3, "xnu")]), \
                    patch.object(b, "api", side_effect=api):
                b.resolve(args)
        self.assertEqual(looked_up, ["/repos/VibeDarling/cocotron/pulls/1"])


if __name__ == "__main__":
    unittest.main()
