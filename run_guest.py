#!/usr/bin/env python3
"""Run the authored core scan fixtures, preserving every run and shutdown receipt.

Requires the owner's heavy slot and a nonblocking shared lock. Receipt JSON names
runtime_root, dyld_relative, dyld_sha256, source_repo, source_sha, launcher_sha256.
Receipts identify committed runtime inputs; they must be prepared by the builder.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile

from build_guest import CORE_PROGRAMS, GUEST_INPUTS, INPUTS, absolute, committed_inputs


GUEST_ROOT = "/Volumes/SystemRoot"
SKIP_DIAGNOSTIC = b"dyld: missing-symbol trace: image scan skipped, the main executable does not require strict Mach-O loading (built for an SDK before macOS 10.15)\n"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo: Path, *args: str) -> str:
    process = subprocess.Popen(["git", "-C", str(repo), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"git deadline exceeded; retained pid {process.pid}") from error
    if process.returncode:
        raise RuntimeError(stderr.decode(errors="replace"))
    return stdout.decode().strip()


def runtime_identity(receipt: Path, launcher: Path) -> dict:
    data = json.loads(receipt.read_text())
    assert set(data) == {"runtime_root", "dyld_relative", "dyld_sha256", "source_repo", "source_sha", "launcher_sha256"}
    root, repo = absolute(data["runtime_root"]), absolute(data["source_repo"])
    relative = Path(data["dyld_relative"])
    assert not relative.is_absolute() and ".." not in relative.parts
    dyld = root / relative
    assert dyld.resolve().is_relative_to(root.resolve())
    assert (root / "usr/local").is_dir()
    assert re.fullmatch(r"[0-9a-f]{40}", data["source_sha"])
    assert git(repo, "rev-parse", "HEAD") == data["source_sha"]
    assert not git(repo, "status", "--porcelain", "--untracked-files=no"), "runtime source has tracked changes"
    assert digest(dyld) == data["dyld_sha256"]
    assert digest(launcher) == data["launcher_sha256"]
    return data


def fixture_identity(package: Path) -> dict:
    manifest = json.loads((package / "manifest.json").read_text())
    assert set(manifest) == {"pr1170_repo", "pr1170_sha", "inputs", "fixture_repo", "fixture_sha", "fixture_inputs", "files"}
    files = manifest["files"]
    assert type(files) is dict
    required = {f"fixtures/arm64/{variant}/{lib}/{name}" for variant in ("opcode", "chained")
                for lib in ("real", "empty") for name in (*CORE_PROGRAMS, "libmst.dylib")}
    required.update(f"source/pr1170/{name}" for name in INPUTS)
    required.update(f"source/guest/{name}" for name in GUEST_INPUTS)
    assert required <= files.keys(), "manifest omits required core artifact/source"
    for relative, expected in files.items():
        assert type(relative) is str and type(expected) is str and re.fullmatch(r"[0-9a-f]{64}", expected)
        path = Path(relative)
        assert not path.is_absolute() and ".." not in path.parts
        path = package / path
        assert path.resolve().is_relative_to(package.resolve())
        assert digest(path) == expected, path
    for repo_key, sha_key, hashes_key, names, source, prefix in (
        ("pr1170_repo", "pr1170_sha", "inputs", INPUTS, "pr1170", "tests/mst/"),
        ("fixture_repo", "fixture_sha", "fixture_inputs", GUEST_INPUTS, "guest", ""),
    ):
        assert type(manifest[repo_key]) is str and type(manifest[sha_key]) is str
        hashes = manifest[hashes_key]
        assert type(hashes) is dict and set(hashes) == set(names)
        inputs = committed_inputs(absolute(manifest[repo_key]), manifest[sha_key], names, prefix)
        for name, data in inputs.items():
            assert type(hashes[name]) is str and re.fullmatch(r"[0-9a-f]{64}", hashes[name])
            assert hashlib.sha256(data).hexdigest() == hashes[name] == files[f"source/{source}/{name}"]
    for name in ("build_guest.py", "run_guest.py"):
        assert digest(Path(__file__).with_name(name)) == manifest["fixture_inputs"][name], f"live {name} differs from committed fixture input"
    return manifest


class Prefix:
    def __init__(self, launcher: Path, identity: dict, root: Path, label: str):
        self.launcher = launcher
        self.root = root / label
        self.root.mkdir(mode=0o700)
        self.prefix = self.root / "p"
        self.prefix.mkdir(mode=0o700)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("DARLING_", "DYLD_", "MST_"))}
        self.env.update(DPREFIX=str(self.prefix), DARLING_INSTALL_PREFIX=str(Path(identity["runtime_root"]) / "usr/local"))
        self.shutdown_attempted = False
        self.sequence = 0

    def launch(self, tag: str, arguments: list[str], deadline: int) -> tuple[subprocess.Popen, Path]:
        self.sequence += 1
        path = self.root / f"{self.sequence:04d}-{tag}"
        with path.with_suffix(".out").open("xb") as stdout, path.with_suffix(".err").open("xb") as stderr:
            process = subprocess.Popen([str(self.launcher), *arguments], env=self.env, stdout=stdout, stderr=stderr)
        path.with_suffix(".pid.json").write_text(json.dumps({"pid": process.pid, "prefix": str(self.prefix), "arguments": arguments}) + "\n")
        try:
            process.communicate(timeout=deadline)
        except subprocess.TimeoutExpired:
            path.with_suffix(".timeout").write_text(f"deadline={deadline}; pid={process.pid}; prefix={self.prefix}\n")
            return process, path
        path.with_suffix(".rc").write_text(f"{process.returncode}\n")
        return process, path

    def stop(self) -> None:
        if self.shutdown_attempted:
            return
        self.shutdown_attempted = True
        process, path = self.launch("shutdown", ["shutdown"], 30)
        if process.returncode != 0:
            raise RuntimeError(f"shutdown failed or exceeded deadline; prefix retained: {self.prefix}; receipts: {path}")

    def guest(self, tag: str, program: str, variables: list[str], deadline: int = 120) -> tuple[int, bytes, bytes]:
        process, path = self.launch(tag, ["shell", "/usr/bin/env", *variables, program], deadline)
        if process.returncode is None:
            shutdown_error = None
            try:
                self.stop()
            except RuntimeError as error:
                shutdown_error = error
            try:
                process.communicate(timeout=30)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(f"launcher retained after shutdown; pid={process.pid}, prefix={self.prefix}, receipts={path}; shutdown={shutdown_error}") from error
            path.with_suffix(".rc").write_text(f"{process.returncode}\n")
            raise RuntimeError(f"guest deadline exceeded; receipts={path}; shutdown={shutdown_error}")
        return process.returncode, path.with_suffix(".out").read_bytes(), path.with_suffix(".err").read_bytes()

    def warmup(self) -> None:
        result = self.guest("warmup", "/usr/bin/true", [], 300)
        assert result[0] == 0, f"warm-up failed: {self.root}"


def read_records(directory: Path, executable: str, *, absent: bool = False) -> list[dict]:
    files = list(directory.iterdir())
    if absent:
        assert not files, f"unexpected log: {files}"
        return []
    assert len(files) == 1, f"expected one log, found {files}"
    path = files[0]
    assert re.fullmatch(re.escape(executable) + r"-[0-9]+-[0-9]+\.jsonl", path.name)
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    raw = path.read_bytes()
    assert len(raw) <= 16 * 1024 * 1024 and raw.endswith(b"\n")
    records = []
    for line in raw.splitlines():
        record = json.loads(line)
        assert type(record.get("v")) is int and record["v"] == 1
        kind = record.get("kind")
        if kind == "missing":
            assert set(record) == {"v", "kind", "sym", "lib", "from", "arch"}
            assert all(type(record[key]) is str for key in ("sym", "lib", "from", "arch"))
            assert record["arch"] == "arm64"
        elif kind == "scan_skipped":
            assert set(record) == {"v", "kind"}
        elif kind == "truncated":
            keys = set(record)
            assert keys in ({"v", "kind"}, {"v", "kind", "reason"}, {"v", "kind", "arch"},
                            {"v", "kind", "lib", "arch"}, {"v", "kind", "from", "arch"},
                            {"v", "kind", "lib", "from", "arch"})
            if "reason" in record:
                assert record["reason"] == "scan_budget"
            for key in keys - {"v", "kind"}:
                assert type(record[key]) is str
            if "arch" in record:
                assert record["arch"] == "arm64"
        else:
            raise AssertionError(f"unknown kind: {kind}")
        records.append(record)
    return records


def assert_missing(records: list[dict], names: set[str], executable: Path, *, skipped: bool = False) -> None:
    expected = [{"v": 1, "kind": "missing", "sym": name,
                 "lib": GUEST_ROOT + str(executable.parent / "libmst.dylib"),
                 "from": GUEST_ROOT + str(executable), "arch": "arm64"} for name in names]
    if skipped:
        expected.append({"v": 1, "kind": "scan_skipped"})
    assert sorted(records, key=lambda row: json.dumps(row, sort_keys=True)) == sorted(expected, key=lambda row: json.dumps(row, sort_keys=True)), records


def run_core(prefix: Prefix, package: Path, label: str) -> dict[str, tuple[int, bytes, bytes]]:
    results = {}
    prefix.warmup()
    controls = {"main_multi": 16, "main_weak": 9, "main_multi_weak": 14, "main_objc": 37}
    misses = {"main_multi": {"_d_data", "_f_int", "_f_fp"}, "main_multi_weak": {"_d_data"},
              "main_objc": {"_OBJC_CLASS_$_MSTMissing"}, "main_multi_oldsdk": {"_d_data"}}
    for variant in ("opcode", "chained"):
        for lib in ("real", "empty"):
            for executable in CORE_PROGRAMS:
                path = package / "fixtures/arm64" / variant / lib / executable
                for on in (False, True) if label == "fix" else (False,):
                    tag = f"{variant}-{lib}-{executable}-{'on' if on else 'off'}"
                    logs = prefix.root / f"logs-{tag}"
                    logs.mkdir(mode=0o700)
                    variables = [f"DARLING_MISSING_SYMBOLS_LOG={GUEST_ROOT}{logs}"]
                    if on:
                        variables.append("DARLING_MISSING_SYMBOLS=log")
                    result = prefix.guest(tag, GUEST_ROOT + str(path), variables)
                    results[tag] = result
                    control = lib == "real" or executable == "main_weak"
                    if control:
                        expected_rc = controls.get(executable, 16) if lib == "real" else 0
                        assert result == (expected_rc, b"", b""), (tag, result)
                    else:
                        assert result[0] not in (0, 124, 127), (tag, result)
                        assert b"Symbol not found:" in result[2], (tag, result)
                    records = read_records(logs, executable, absent=not on or control)
                    if on and not control:
                        oldsdk = executable == "main_multi_oldsdk"
                        assert_missing(records, misses[executable], path, skipped=oldsdk)
                        off = results[tag.removesuffix("on") + "off"]
                        if oldsdk:
                            assert result[2].count(SKIP_DIAGNOSTIC) == 1
                            assert (result[0], result[1], result[2].replace(SKIP_DIAGNOSTIC, b"", 1)) == off
                        else:
                            assert result == off, f"tracing changed observable result: {tag}"
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher", type=absolute, required=True)
    parser.add_argument("--base-receipt", type=absolute, required=True)
    parser.add_argument("--fix-receipt", type=absolute, required=True)
    parser.add_argument("--package", type=absolute, required=True)
    args = parser.parse_args()
    assert os.access(args.launcher, os.X_OK) and not args.launcher.stat().st_mode & stat.S_ISUID
    identities = {label: runtime_identity(receipt, args.launcher) for label, receipt in
                  (("base", args.base_receipt), ("fix", args.fix_receipt))}
    manifest = fixture_identity(args.package)
    lock_path = Path("/tmp/agent-locks/darling-heavy-build.lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        root = Path(tempfile.mkdtemp(prefix="mstg-", dir="/tmp"))
        print(f"artifacts retained: {root}", flush=True)
        (root / "identities.json").write_text(json.dumps({"runtimes": identities, "fixtures": manifest}, indent=2) + "\n")
        results = {}
        for label in ("base", "fix"):
            prefix = Prefix(args.launcher, identities[label], root, label)
            try:
                results[label] = run_core(prefix, args.package, label)
            finally:
                prefix.stop()
        for tag, baseline in results["base"].items():
            assert results["fix"][tag] == baseline, f"default-off differs from base: {tag}"
        print("PASS core t3/t5 and SDK-field gate; shutdown complete")


if __name__ == "__main__":
    main()
