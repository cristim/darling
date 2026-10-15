#!/usr/bin/env python3
"""Host-only tests in a nested public layout with a minimal pinned object fixture."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

from build_guest import GUEST_SESSION_SHA256, PR1170_SHA
from test_fixture_provenance import git
import test_support
from test_support import canonical_source


def main() -> None:
    source = Path(__file__).resolve().parent
    canonical_repo, canonical = canonical_source()
    root = Path(tempfile.mkdtemp(prefix="mst-helper-layout-", dir="/tmp"))
    print(f"public-layout receipts retained: {root}", flush=True)
    repo = root / "public-layout"
    repo.mkdir()
    git(repo, "init", "--quiet")
    for selected, expected in (("relative", "absolute repository path"), (str(root / "missing"), "fixed reviewed commit"), (str(repo), "fixed reviewed commit")):
        with patch.dict(os.environ, MST_TEST_CANONICAL_REPO=selected):
            try:
                canonical_source()
            except (ValueError, RuntimeError) as error:
                assert expected in str(error), error
            else:
                raise AssertionError("invalid explicit canonical repository accepted")
    with patch.dict(os.environ, MST_TEST_CANONICAL_REPO=str(canonical_repo)):
        for target, replacement in (("committed_inputs", {"guest_session.py": b"unreviewed = True\n"}), ("command", b"0" * 40)):
            with patch.object(test_support, target, return_value=replacement):
                try:
                    canonical_source()
                except ValueError as error:
                    assert "fixed reviewed digest/blob" in str(error)
                else:
                    raise AssertionError("invalid canonical helper digest/blob accepted")
    print("PASS explicit repository failures and fixed helper identity", flush=True)

    for kind, reference in (("commit", PR1170_SHA), ("tree", PR1170_SHA + "^{tree}"), ("tree", PR1170_SHA + ":tests"), ("tree", PR1170_SHA + ":tests/mst"), ("blob", PR1170_SHA + ":tests/mst/guest_session.py")):
        identity = git(canonical_repo, "rev-parse", reference).decode().strip()
        data = git(canonical_repo, "cat-file", kind, identity)
        copied = subprocess.run(["git", "-C", str(repo), "hash-object", "-t", kind, "-w", "--stdin"], input=data, capture_output=True, check=True, timeout=10).stdout.decode().strip()
        assert copied == identity
    helper = repo / "tests/mst/guest_session.py"
    helper.parent.mkdir(parents=True)
    helper.write_bytes(canonical)
    nested = repo / "tests/scan"
    files = set(git(source, "ls-files", "-z").decode().split("\0"))
    files.update(("test_support.py", "test_helper_portability.py"))
    for name in sorted(files - {""}):
        destination = nested / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes((source / name).read_bytes())
    git(repo, "add", "--", "tests/scan")
    environment = {key: value for key, value in os.environ.items() if key != "MST_TEST_CANONICAL_REPO"}
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    no_history = subprocess.run(["git", "-C", str(repo), "cat-file", "-e", "e1719a689bae6a00bcb51b51f1a2e34428e5c49b"], capture_output=True, timeout=10)
    assert no_history.returncode != 0
    results = {}
    for name in ("test_guest_runner.py", "test_fixture_provenance.py", "test_helper_migration_probes.py"):
        result = subprocess.run([sys.executable, "-B", name], cwd=nested, env=environment, capture_output=True, timeout=40)
        (root / (name + ".stdout")).write_bytes(result.stdout)
        (root / (name + ".stderr")).write_bytes(result.stderr)
        results[name] = result.returncode
        assert result.returncode == 0, (name, result.stderr, result.stdout)
        print(f"PASS nested public default: {name}", flush=True)
    (root / "result.json").write_text(json.dumps({"results": results, "private_staging_commit_absent": True, "canonical_sha256": GUEST_SESSION_SHA256, "fixture": "five exact source Git objects; no ancestry or unrelated tree objects"}, indent=2) + "\n")


if __name__ == "__main__":
    main()
