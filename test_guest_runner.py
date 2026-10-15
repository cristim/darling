#!/usr/bin/env python3
"""Host-only lifecycle checks; no compiler, Darling runtime or heavy lock."""

import json
from pathlib import Path
import sys
import tempfile

from run_guest import Prefix, read_records


def fake_prefix(root: Path, behavior: str) -> Prefix:
    launcher = root / "launcher"
    launcher.write_text(
        f"#!{sys.executable}\n"
        "import json, os, pathlib, sys, time\n"
        "root = pathlib.Path(os.environ['DPREFIX']).parent\n"
        "with (root / 'calls.jsonl').open('a') as output:\n"
        "    output.write(json.dumps({'args':sys.argv[1:],'prefix':os.environ['DPREFIX']})+'\\n')\n"
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
    return Prefix(launcher, {"runtime_root": str(root / "runtime")}, root, "case")


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
    prefix.stop()
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
    except AssertionError as error:
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
    sys.exit(main())
