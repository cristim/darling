#!/usr/bin/env python3
"""Host-only current-source mutations in separate scratch trees."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from test_support import canonical_source


def main() -> None:
    source = Path(__file__).resolve().parent
    receipts = Path(tempfile.mkdtemp(prefix="mst-helper-probes-", dir="/tmp"))
    print(f"migration probes retained: {receipts}")
    canonical_repo, _ = canonical_source()
    driver = (source / "run_guest.py").read_text()
    mutations = (
        ("import-before-validation", "    manifest, helper = fixture_identity(args.package)\n", "    load_guest_session(args.package, (args.package / 'source/pr1170/guest_session.py').read_bytes())\n    manifest, helper = fixture_identity(args.package)\n", "test_fixture_provenance", "test_helper_authentication_before_execution"),
        ("arbitrary-source-pin", '    assert manifest["pr1170_sha"] == PR1170_SHA, "unreviewed canonical source commit"\n', "", "test_fixture_provenance", "test_alternate_valid_commit_cannot_choose_trusted_pin"),
        ("renew-per-prefix", '            prefix = session.Prefix(args.launcher, identities[label], root, label, overall)\n', '            overall = session.Deadline(args.overall_deadline)\n            prefix = session.Prefix(args.launcher, identities[label], root, label, overall)\n', "test_guest_runner", "test_scan_shared_deadline_and_cleanup_failure"),
        ("omit-final-budget", '        overall.budget(1)\n        for tag, baseline in results["base"].items():\n            assert results["fix"][tag] == baseline, f"default-off differs from base: {tag}"\n        overall.budget(1)\n', '        for tag, baseline in results["base"].items():\n            assert results["fix"][tag] == baseline, f"default-off differs from base: {tag}"\n', "test_guest_runner", "test_scan_shared_deadline_and_cleanup_failure"),
        ("allocate-before-lock-validation", '    with session.HeavyLock(args.inherited_lock_fd):\n        overall.budget(1)\n        root = Path(tempfile.mkdtemp(prefix="mstg-", dir="/tmp"))\n', '    root = Path(tempfile.mkdtemp(prefix="mstg-", dir="/tmp"))\n    with session.HeavyLock(args.inherited_lock_fd):\n        overall.budget(1)\n', "test_guest_runner", "test_inherited_lock_cli_retains_parent_ownership"),
    )
    files = set(subprocess.check_output(["git", "-C", str(source), "ls-files", "-z"], timeout=10).decode().split("\0"))
    files.add("test_support.py")
    for name, before, after, module, test in mutations:
        assert driver.count(before) == 1, name
        scratch = Path(tempfile.mkdtemp(prefix=f"helper-probe-{name}-", dir=source.parent))
        for filename in sorted(files):
            if filename:
                destination = scratch / filename
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((source / filename).read_bytes())
        (scratch / "run_guest.py").write_text(driver.replace(before, after))
        case = scratch / "probe-case"
        case.mkdir()
        invocation = f"from pathlib import Path; import {module}; {module}.{test}(Path('probe-case').resolve())"
        environment = dict(os.environ, MST_TEST_CANONICAL_REPO=str(canonical_repo), PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([sys.executable, "-B", "-c", invocation], cwd=scratch, env=environment, capture_output=True, timeout=20)
        (scratch / "stdout").write_bytes(result.stdout)
        (scratch / "stderr").write_bytes(result.stderr)
        assert result.returncode != 0 and b"AssertionError" in result.stderr, (name, result.stderr)
        if name == "import-before-validation":
            assert (case / "untrusted-executed").exists(), result.stderr
        if name == "allocate-before-lock-validation":
            assert b"invalid FD allocated invocation root" in result.stderr, result.stderr
            assert json.loads((case / "closed/allocations.json").read_text()) == [{"prefix": "mstg-", "dir": "/tmp"}]
            assert (case / "closed/scan").is_dir()
        (receipts / f"{name}.json").write_text(json.dumps({"scratch": str(scratch), "status": result.returncode}) + "\n")
        print(f"PASS mutation killed: {name} ({test})")


if __name__ == "__main__":
    main()
