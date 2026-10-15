#!/usr/bin/env python3
"""Host-only lifecycle checks; no compiler, Darling runtime or heavy lock."""

from datetime import datetime, timedelta, timezone
from contextlib import ExitStack, nullcontext, redirect_stdout
import fcntl
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

import run_guest
from run_guest import load_guest_session, read_records
from test_support import canonical_source


def canonical_session():
    _, data = canonical_source()
    return load_guest_session(Path("/verified-package"), data)


session = canonical_session()
Prefix = session.Prefix


def overall():
    return session.Deadline((datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat())


def fake_prefix(root: Path, behavior: str, forbidden_lock: Path | None = None) -> Prefix:
    launcher = root / "launcher"
    launcher.write_text(
        f"#!{sys.executable}\n"
        "import json, os, pathlib, sys, time\n"
        f"lock = {str(forbidden_lock) if forbidden_lock else None!r}\n"
        "leaked = False\n"
        "if lock is not None:\n"
        "    intended = os.stat(lock)\n"
        "    for fd in range(3, 256):\n"
        "        try:\n"
        "            actual = os.fstat(fd)\n"
        "        except OSError:\n"
        "            continue\n"
        "        leaked |= (actual.st_dev, actual.st_ino) == (intended.st_dev, intended.st_ino)\n"
        "root = pathlib.Path(os.environ['DPREFIX']).parent\n"
        "with (root / 'calls.jsonl').open('a') as output:\n"
        "    output.write(json.dumps({'args':sys.argv[1:],'prefix':os.environ['DPREFIX'],'leaked':leaked})+'\\n')\n"
        f"behavior = {behavior!r}\n"
        "if sys.argv[1:] == ['shutdown']:\n"
        "    (root / 'released').touch()\n"
        "    sys.exit(9 if behavior == 'shutdown-fail' else 0)\n"
        "if behavior == 'warmup-fail':\n"
        "    sys.exit(7)\n"
        "if behavior == 'wait-for-shutdown':\n"
        "    for attempt in range(1000):\n"
        "        if (root / 'released').exists():\n"
        "            sys.exit(8)\n"
        "        time.sleep(0.01)\n"
        "    sys.exit(10)\n"
    )
    launcher.chmod(0o700)
    return Prefix(launcher, {"runtime_root": str(root / "runtime")}, root, "case", overall())


def calls(prefix: Prefix) -> list[dict]:
    result = [json.loads(line) for line in (prefix.root / "calls.jsonl").read_text().splitlines()]
    assert {entry["prefix"] for entry in result} == {str(prefix.prefix)}
    assert sum(entry["args"] == ["shutdown"] for entry in result) == 1
    return result


def test_success(root: Path) -> None:
    prefix = fake_prefix(root, "success")
    prefix.warmup()
    prefix.stop()
    prefix.stop()
    assert len(calls(prefix)) == 2
    assert (prefix.root / "0002-shutdown.rc").read_text() == "0\n"


def test_shutdown_failure(root: Path) -> None:
    prefix = fake_prefix(root, "shutdown-fail")
    prefix.warmup()
    try:
        prefix.stop()
    except RuntimeError as error:
        assert "prefix retained" in str(error)
    else:
        raise AssertionError("shutdown failure ignored")
    try:
        prefix.stop()
    except RuntimeError as error:
        assert "prefix retained" in str(error)
    else:
        raise AssertionError("repeated shutdown failure ignored")
    assert len(calls(prefix)) == 2
    assert prefix.prefix.is_dir()
    assert (prefix.root / "0002-shutdown.rc").read_text() == "9\n"


def test_warmup_failure(root: Path) -> None:
    prefix = fake_prefix(root, "warmup-fail")
    try:
        try:
            prefix.warmup()
        finally:
            prefix.stop()
    except RuntimeError as error:
        assert "warm-up failed" in str(error)
    else:
        raise AssertionError("warmup failure ignored")
    assert len(calls(prefix)) == 2


def test_timeout_shutdown_then_reap(root: Path) -> None:
    prefix = fake_prefix(root, "wait-for-shutdown")
    try:
        prefix.guest("waiting", "/fixture", [], deadline=0.1)
    except RuntimeError as error:
        assert "guest deadline exceeded" in str(error)
    else:
        raise AssertionError("timeout ignored")
    prefix.stop()
    entries = calls(prefix)
    assert len(entries) == 2 and entries[0]["args"][0] == "shell"
    assert (prefix.root / "released").exists()
    assert (prefix.root / "0001-waiting.timeout").is_file()
    assert (prefix.root / "0001-waiting.rc").read_text() == "8\n"


def test_schema_rejects_unknown_fields(root: Path) -> None:
    log = root / "fixture-1-1.jsonl"
    log.write_text('{"v":1,"kind":"missing","sym":"_x","lib":"flat namespace","from":"/fixture","arch":"arm64","addr":0}\n')
    log.chmod(0o600)
    try:
        read_records(root, "fixture")
    except AssertionError:
        pass
    else:
        raise AssertionError("forbidden field accepted")


def scan_main(root: Path, *, consume: str = "", inherited: str | None = None, lock_path: Path | None = None) -> str:
    prefix = fake_prefix(root, "shutdown-fail" if consume == "shutdown" else "success", lock_path)
    launcher = prefix.launcher
    clock = [0.0]
    observed = []
    def identity(*arguments):
        if consume == "setup":
            clock[0] = 1000
        return {"runtime_root": str(root / "runtime")}

    def core(prefix, package, label):
        observed.append((label, prefix.overall))
        prefix.warmup()
        if consume == label:
            clock[0] = 550
        return {"ordinary-off": (0, b"", b"")}

    args = ["run_guest.py", "--launcher", str(launcher), "--base-receipt", "/tmp/base", "--fix-receipt", "/tmp/fix", "--package", str(root), "--overall-deadline", (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()]
    if inherited is not None:
        args.extend(("--inherited-lock-fd", inherited))
    _, data = canonical_source()
    output = io.StringIO()
    scan_root = root / "scan"
    allocations = []
    def allocate(**arguments):
        allocations.append(arguments)
        scan_root.mkdir(mode=0o700)
        return str(scan_root)

    with ExitStack() as stack:
        for target, name, replacement in ((sys, "argv", args), (run_guest, "fixture_identity", lambda package: ({}, data)), (run_guest, "load_guest_session", lambda package, verified: session), (session, "runtime_identity", identity), (run_guest.tempfile, "mkdtemp", allocate), (run_guest, "run_core", core), (session.time, "monotonic", lambda: clock[0])):
            stack.enter_context(patch.object(target, name, replacement))
        for name in ("run_t8", "run_t9", "run_aliases", "run_fork"):
            stack.enter_context(patch.object(run_guest, name, return_value={}))
        if lock_path is None:
            stack.enter_context(patch.object(session, "HeavyLock", lambda inherited: nullcontext()))
        else:
            stack.enter_context(patch.object(session, "LOCK_PATH", lock_path))
        try:
            with redirect_stdout(output):
                run_guest.main()
        finally:
            (root / "stdout").write_text(output.getvalue())
            (root / "sessions.json").write_text(json.dumps([label for label, _ in observed]))
            (root / "allocations.json").write_text(json.dumps(allocations))
    assert [label for label, _ in observed] == ["base", "fix"]
    assert observed[0][1] is observed[1][1]
    return output.getvalue()


def test_scan_shared_deadline_and_cleanup_failure(root: Path) -> None:
    for failure in ("setup", "base", "fix", "shutdown", "success"):
        case = root / failure
        case.mkdir()
        try:
            output = scan_main(case, consume=failure)
        except RuntimeError:
            assert failure != "success"
            assert "PASS" not in (case / "stdout").read_text()
            labels = json.loads((case / "sessions.json").read_text())
            assert labels == ([] if failure == "setup" else ["base", "fix"] if failure == "fix" else ["base"])
        else:
            assert failure == "success" and "PASS" in output


def test_exit124_is_ordinary_and_session_scrubs_environment(root: Path) -> None:
    prefix = fake_prefix(root, "success")
    with prefix.launcher.open("a") as script:
        script.write("sys.exit(124)\n")
    with patch.dict(os.environ, {"MST_LOCKED": "1", "DYLD_TEST": "x", "DARLING_TEST": "x", "DPREFIX": "/unowned"}):
        tested = Prefix(prefix.launcher, {"runtime_root": str(root / "runtime")}, root, "scrub", overall())
    assert not any(key in tested.env for key in ("MST_LOCKED", "DYLD_TEST", "DARLING_TEST"))
    assert tested.guest("ordinary124", "/fixture", []) == (124, b"", b"")
    tested.stop()


def test_inherited_lock_cli_retains_parent_ownership(root: Path) -> None:
    lock = root / "authored.lock"
    owner = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    contender = os.open(lock, os.O_RDWR)
    wrong = os.open(root / "other.lock", os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        for name, fd, passed, succeeds in (("valid", str(owner), (owner,), True), ("closed", "99999", (), False), ("contended", str(contender), (contender,), False), ("wrong", str(wrong), (wrong,), False)):
            case = root / name
            case.mkdir()
            child = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--cli-child", str(case), fd, str(lock)], pass_fds=passed, capture_output=True, timeout=20)
            assert (child.returncode == 0) == succeeds, child.stderr
            if succeeds:
                assert json.loads((case / "allocations.json").read_text()) == [{"prefix": "mstg-", "dir": "/tmp"}]
                records = [json.loads(line) for path in (case / "scan").glob("*/calls.jsonl") for line in path.read_text().splitlines()]
                assert len(records) == 4 and not any(record["leaked"] for record in records)
            else:
                assert json.loads((case / "allocations.json").read_text()) == [], "invalid FD allocated invocation root"
                assert not (case / "scan").exists(), "invalid FD created invocation root"
                assert not list(case.rglob("calls.jsonl")), "invalid FD launched a guest"
                assert "PASS" not in (case / "stdout").read_text()
            try:
                fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise AssertionError("scan child released parent's OFD lock")
    finally:
        os.close(owner)
        os.close(wrong)
    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
    os.close(contender)


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="mst-runner-host-", dir="/tmp"))
    print(f"host receipts retained: {root}")
    failures = 0
    for name, test in list(globals().items()):
        if name.startswith("test_"):
            case = root / name
            case.mkdir(mode=0o700)
            try:
                test(case)
            except AssertionError as error:
                failures += 1
                print(f"FAIL {name}: {error}")
            else:
                print(f"PASS {name}")
    return int(failures != 0)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--cli-child":
        scan_main(Path(sys.argv[2]), inherited=sys.argv[3], lock_path=Path(sys.argv[4]))
    else:
        sys.exit(main())
