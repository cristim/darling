#!/usr/bin/env python3
"""Host-only text/JSON controllers; does not execute C or a Darling guest."""

import json
from pathlib import Path
import tempfile
from unittest.mock import patch

import run_guest as runner


def rejected(call) -> None:
    try:
        call()
    except (AssertionError, FileExistsError):
        return
    raise AssertionError("negative control was accepted")


class FakePrefix:
    def __init__(self, root: Path, attack: str = ""):
        self.root = root
        root.mkdir()
        self.prefix = root / "p"
        self.prefix.mkdir()
        self.attack = attack
        self.calls = []
        self.stops = 0

    def stop(self):
        self.stops += 1
        if self.attack == "shutdown":
            raise RuntimeError("shutdown failed; prefix retained")

    def guest(self, tag, program, variables, program_arguments=()):
        self.calls.append((tag, variables))
        if tag == "fork-home":
            if self.attack == "preexisting":
                (self.prefix / "Users/test/fork-opcode-s-unset/Library/Logs/Darling/MissingSymbols").mkdir(parents=True)
            return 0, b"/Users/test", b""
        env = dict(value.split("=", 1) for value in variables)
        assert "HOME" in env
        assert ("DARLING_MISSING_SYMBOLS_LOG" in env) == tag.endswith(("-on", "-explicit"))
        assert ("DARLING_MISSING_SYMBOLS" in env) == (not tag.endswith("-unset"))
        first, second = (Path(value.removeprefix(runner.GUEST_ROOT)) for value in program_arguments[:2])
        stdout = b"prefork: " + runner.dlopen_error(first, "_mst_thread_a") + b"\n"
        stdout += b"child: " + runner.dlopen_error(second, "_mst_thread_b") + b"\n"
        stdout += b"parent: " + runner.dlopen_error(first, "_mst_thread_a") + b"\n"
        if self.attack == "markers":
            stdout = b"prefork: \nchild: \nparent: \n"
        elif self.attack == "phase":
            stdout = stdout.replace(b"child: ", b"prefork: ")
        elif self.attack == "error":
            stdout = stdout.replace(b"_mst_thread_b", b"_other")
        elif self.attack == "order":
            stdout = stdout.replace(b"prefork: ", b"parent: ", 1)
        if self.attack == "default-created":
            (self.prefix / env["HOME"].lstrip("/") / "Library/Logs/Darling/MissingSymbols").mkdir(parents=True)
        if "DARLING_MISSING_SYMBOLS_LOG" in env:
            logs = Path(env["DARLING_MISSING_SYMBOLS_LOG"].removeprefix(runner.GUEST_ROOT))
            on = env.get("DARLING_MISSING_SYMBOLS") == "log"
            if on or self.attack == "off-log":
                a = {"v": 1, "kind": "missing", "sym": "_mst_thread_a", "lib": "flat namespace", "from": runner.GUEST_ROOT + str(first), "arch": "arm64"}
                b = dict(a, sym="_mst_thread_b", **{"from": runner.GUEST_ROOT + str(second)})
                final = {"v": 1, "kind": "truncated"}
                counter = program_arguments[2] == "c"
                rows = [a] * 4095 + [b, final, a, final] if counter else [a, b, a]
                if counter and self.attack == "shared-counter":
                    rows = [a] * 4095 + [b, final]
                elif counter and self.attack == "reset-counter":
                    rows = [a] * 4095 + [b, b, a, a]
                elif counter and self.attack == "extra-final":
                    rows.append(final)
                elif self.attack == "row-order":
                    rows = [b, a, a]
                elif self.attack == "row-error":
                    rows = [dict(a, sym="_wrong"), b, a]
                path = logs / "main_fork-1-1.jsonl"
                path.write_text("".join(json.dumps(row) + "\n" for row in rows))
                path.chmod(0o600)
                if self.attack == "extra-log":
                    (logs / "main_fork-2-2.jsonl").write_text("{}\n")
        return (3 if self.attack == "status" else 0), stdout, (b"unexpected" if self.attack == "stderr" else b"")


def main():
    root = Path(tempfile.mkdtemp(prefix="mst-fork-host-"))
    package = root / "package"
    for label, count in (("base", 12), ("fix", 16)):
        prefix = FakePrefix(root / label)
        result = runner.run_fork(prefix, package, label)
        assert len(result) == count and len(prefix.calls) == count + 1
    attacks = ("markers", "phase", "error", "order", "status", "stderr", "default-created", "preexisting",
               "off-log", "shared-counter", "reset-counter", "extra-final", "extra-log", "row-order", "row-error")
    for attack in attacks:
        prefix = FakePrefix(root / attack, attack)
        rejected(lambda: runner.run_fork(prefix, package, "fix"))
    for attack in ("markers", "shutdown"):
        prefix = FakePrefix(root / f"lifecycle-{attack}", attack)
        with patch.object(runner, "run_core", return_value={}), patch.object(runner, "run_t8", return_value={}), \
                patch.object(runner, "run_t9", return_value={}), patch.object(runner, "run_aliases", return_value={}):
            try:
                runner.run_checks(prefix, package, "fix", {})
            except (AssertionError, RuntimeError):
                pass
            else:
                raise AssertionError("failure escaped lifecycle")
        assert prefix.stops == 1
    for validator, attack in (("assert_fork_result", "markers"), ("assert_fork_records", "shared-counter")):
        prefix = FakePrefix(root / f"deletion-{attack}", attack)
        with patch.object(runner, validator, return_value=None):
            runner.run_fork(prefix, package, "fix")
    print(f"PASS positive base/fix matrices, {len(attacks)} negative controllers, 2 shutdown paths, 2 validator deletion probes; retained {root}")


if __name__ == "__main__":
    main()
