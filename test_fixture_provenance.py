#!/usr/bin/env python3
"""Host-only provenance preflight tests with a fresh authored Git repository."""

import copy
from contextlib import redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import ModuleType
from unittest.mock import patch

import build_guest
import run_guest
from alias_guest import LAYOUT, LEAVES, compile_sources as compile_alias_sources
from many_guest import NAMES
from test_support import canonical_source


GUEST_INPUTS = build_guest.GUEST_INPUTS
PROGRAMS = ("main_multi", "main_weak", "main_multi_weak", "main_objc", "main_multi_oldsdk", "main_many", "main_dlopen", "libmst.dylib")
LOAD_SESSION = run_guest.load_guest_session


class ExecutionReached(Exception):
    pass


def git(repo: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *arguments], stderr=subprocess.STDOUT, timeout=10)


def package(root: Path, helper: bytes = b"verified = True\n") -> tuple[Path, dict]:
    repo = root / "repo"
    repo.mkdir()
    git(repo, "init", "--quiet")
    for name in build_guest.INPUTS:
        path = repo / "tests/mst" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(helper if name == "guest_session.py" else f"/* authored fixture input: {name} */\n".encode())
    for name in GUEST_INPUTS:
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((Path(__file__).parent / name).read_bytes())
    git(repo, "add", "--", "tests/mst", *GUEST_INPUTS)
    git(repo, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "test: retain authored provenance inputs")
    sha = git(repo, "rev-parse", "HEAD").decode().strip()
    result = root / "package"
    result.mkdir()
    for prefix, names, destination in (("tests/mst/", build_guest.INPUTS, "pr1170"), ("", GUEST_INPUTS, "guest")):
        for name in names:
            path = result / "source" / destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(git(repo, "show", f"{sha}:{prefix}{name}"))
    for variant in ("opcode", "chained"):
        for lib in ("real", "empty"):
            for name in PROGRAMS:
                path = result / "fixtures/arm64" / variant / lib / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"authored placeholder; never executable: {variant}/{lib}/{name}\n")
        for name in ("main_threads", "main_local", "main_fork"):
            path = result / "fixtures/arm64" / variant / "real" / name
            path.write_text("authored non-executable thread/local placeholder\n")
        for name in ("b_short", "b_long4095", "b_long4096", "b_thread_a", "b_thread_b", "b_self"):
            path = result / "fixtures/arm64" / variant / "bundles" / f"{name}.bundle"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("authored non-executable bundle placeholder\n")
        for kind, libraries in LAYOUT.items():
            base = result / "fixtures/arm64" / variant / "aliases" / kind
            for mode in ("control", "missing"):
                for name in (*libraries, "libtrigger.dylib", "main_alias"):
                    path = base / mode / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("authored non-executable alias placeholder\n")
            path = base / "original" / LEAVES[kind][0]
            path.parent.mkdir()
            path.write_text("authored original-leaf placeholder\n")
    for name in ("libmany.c", "main_many.c"):
        path = result / "source/generated" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("/* authored generated-source placeholder */\n")
    files = {str(path.relative_to(result)): hashlib.sha256(path.read_bytes()).hexdigest() for path in result.rglob("*") if path.is_file()}
    manifest = {"pr1170_repo": str(repo), "pr1170_sha": sha,
                "inputs": {name: files[f"source/pr1170/{name}"] for name in build_guest.INPUTS},
                "fixture_repo": str(repo), "fixture_sha": sha,
                "fixture_inputs": {name: files[f"source/guest/{name}"] for name in GUEST_INPUTS},
                "many_imports": {variant: list(NAMES) for variant in ("opcode", "chained")}, "files": files}
    return result, manifest


def preflight(package_path: Path, manifest: dict, *, should_reach: bool, trusted: dict | None = None, marker: Path | None = None) -> None:
    (package_path / "manifest.json").write_text(json.dumps(manifest))
    arguments = ["run_guest.py", "--launcher", sys.executable, "--base-receipt", "/tmp/base-receipt", "--fix-receipt", "/tmp/fix-receipt", "--package", str(package_path), "--overall-deadline", "2099-01-01T00:00:00Z"]
    reached = False
    trusted = manifest if trusted is None else trusted
    def execute(package_path: Path, data: bytes) -> ModuleType:
        LOAD_SESSION(package_path, data)
        raise ExecutionReached

    with patch.object(sys, "argv", arguments), patch.object(run_guest, "PR1170_SHA", trusted["pr1170_sha"]), patch.object(run_guest, "GUEST_SESSION_SHA256", trusted["inputs"]["guest_session.py"]), patch.object(run_guest, "load_guest_session", side_effect=execute), patch.object(run_guest.tempfile, "mkdtemp") as resource, patch.object(run_guest, "commands", return_value=[]), patch.object(run_guest, "import_order", return_value=list(NAMES)), patch.object(run_guest, "assert_flat"), patch.object(run_guest, "assert_self"), patch.object(run_guest, "assert_pair"):
        try:
            run_guest.main()
        except ExecutionReached:
            reached = True
        except (AssertionError, ValueError, KeyError, TypeError, FileNotFoundError):
            pass
        resource.assert_not_called()
    assert reached == should_reach, "invalid package reached execution boundary" if reached else "valid package rejected"
    if marker is not None:
        assert not marker.exists(), "invalid helper executed"


def test_empty_and_partial_files(root: Path) -> None:
    output, original = package(root)
    preflight(output, original, should_reach=True)
    invalid = copy.deepcopy(original)
    invalid["files"] = {}
    preflight(output, invalid, should_reach=False, trusted=original)
    for required in ("fixtures/arm64/opcode/empty/main_multi", "fixtures/arm64/chained/real/libmst.dylib", "source/guest/fx/main_objc.c",
                     "fixtures/arm64/chained/empty/main_many", "fixtures/arm64/opcode/bundles/b_long4095.bundle"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False, trusted=original)
    for required in ("fixtures/arm64/opcode/real/main_threads", "fixtures/arm64/chained/bundles/b_self.bundle",
                     "fixtures/arm64/opcode/real/main_fork", "fixtures/arm64/chained/real/main_fork", "source/guest/fx/main_fork.c"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False, trusted=original)
    for required in ("fixtures/arm64/opcode/aliases/cycle/missing/main_alias", "fixtures/arm64/chained/aliases/diamond/control/libC.dylib",
                     "fixtures/arm64/opcode/aliases/cycle/original/libA.dylib"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False, trusted=original)


def test_invalid_digest_and_source_metadata(root: Path) -> None:
    output, original = package(root)
    for field, value in (("inputs", {}), ("fixture_inputs", {}), ("fixture_sha", "bad")):
        invalid = copy.deepcopy(original)
        invalid[field] = value
        preflight(output, invalid, should_reach=False, trusted=original)
    invalid = copy.deepcopy(original)
    invalid["files"]["fixtures/arm64/opcode/empty/main_multi"] = 5
    preflight(output, invalid, should_reach=False, trusted=original)
    invalid = copy.deepcopy(original)
    invalid["inputs"]["main_multi.c"] = "0" * 64
    preflight(output, invalid, should_reach=False, trusted=original)


def test_compile_retained_committed_sources(root: Path) -> None:
    output, manifest = package(root)
    repo = Path(manifest["fixture_repo"])
    pinned = build_guest.committed_inputs(repo, manifest["fixture_sha"], GUEST_INPUTS)
    for name in GUEST_INPUTS:
        (repo / name).write_text("/* later working-tree mutation */\n")
    destination = root / "retained"
    hashes = build_guest.retain_inputs(destination, pinned)
    assert hashes == manifest["fixture_inputs"]
    invoked = []

    def fake_compile(arguments: list[str]) -> bytes:
        assert arguments[:2] == ["fake-compiler", "-c"]
        source = Path(arguments[2])
        assert source.parent == destination / "fx"
        assert source.read_bytes() == pinned[f"fx/{source.name}"]
        assert source.read_bytes() != (repo / "fx" / source.name).read_bytes()
        invoked.append(source.name)
        return b""

    with patch.object(build_guest, "command", side_effect=fake_compile):
        build_guest.compile_guest(["fake-compiler"], destination, output / "obj")
    assert set(invoked) == {"libguest.c", "main_multi_weak.c", "main_objc.c", "main_fork.c"}
    alias_calls = []

    def fake_alias_compile(arguments: list[str]) -> bytes:
        assert arguments[:2] == ["fake-compiler", "-c"]
        source = Path(arguments[2])
        assert source.parent == destination / "fx"
        assert source.read_bytes() == pinned[f"fx/{source.name}"]
        assert source.read_bytes() != (repo / "fx" / source.name).read_bytes()
        alias_calls.append(arguments)
        return b""

    compile_alias_sources(["fake-compiler"], output / "obj", destination, fake_alias_compile)
    assert len(alias_calls) == 6
    assert {Path(arguments[2]).name for arguments in alias_calls} == {"alias_leaf.c", "alias_trigger.c", "main_alias.c"}
    assert {value for arguments in alias_calls for value in arguments if value.startswith("-DALIAS_EXPECT=")} == {"-DALIAS_EXPECT=71", "-DALIAS_EXPECT=83"}


def test_source_snapshot_and_live_runner_mismatch(root: Path) -> None:
    output, original = package(root)
    source = output / "source/guest/fx/main_objc.c"
    source.write_text("/* replaced retained source */\n")
    invalid = copy.deepcopy(original)
    invalid["files"]["source/guest/fx/main_objc.c"] = hashlib.sha256(source.read_bytes()).hexdigest()
    preflight(output, invalid, should_reach=False, trusted=original)
    source.write_bytes(git(Path(original["fixture_repo"]), "show", f"{original['fixture_sha']}:fx/main_objc.c"))
    with patch.object(run_guest, "digest", wraps=run_guest.digest) as digest:
        digest.side_effect = lambda path: "0" * 64 if path == Path(run_guest.__file__).with_name("run_guest.py") else hashlib.sha256(path.read_bytes()).hexdigest()
        preflight(output, original, should_reach=False)


def test_helper_authentication_before_execution(root: Path) -> None:
    output, original = package(root)
    helper = output / "source/pr1170/guest_session.py"
    marker = root / "untrusted-executed"
    attack = f"from pathlib import Path\nPath({str(marker)!r}).touch()\n".encode()
    helper.write_bytes(attack)
    preflight(output, original, should_reach=False, marker=marker)
    helper.write_bytes(b"verified = True\n")
    for field, name in (("files", "source/pr1170/guest_session.py"), ("inputs", "guest_session.py")):
        invalid = copy.deepcopy(original)
        del invalid[field][name]
        preflight(output, invalid, should_reach=False, trusted=original, marker=marker)
    helper.rename(helper.with_suffix(".retained"))
    preflight(output, original, should_reach=False, marker=marker)
    helper.write_bytes(attack)
    preflight(output, original, should_reach=False, marker=marker)
    invalid = copy.deepcopy(original)
    invalid["inputs"]["guest_session.py"] = hashlib.sha256(attack).hexdigest()
    invalid["files"]["source/pr1170/guest_session.py"] = invalid["inputs"]["guest_session.py"]
    preflight(output, invalid, should_reach=False, trusted=original, marker=marker)
    repo = Path(original["pr1170_repo"])
    (repo / "tests/mst/guest_session.py").write_bytes(attack)
    git(repo, "add", "tests/mst/guest_session.py")
    git(repo, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "test: alternate helper")
    invalid["pr1170_sha"] = git(repo, "rev-parse", "HEAD").decode().strip()
    preflight(output, invalid, should_reach=False, trusted=original, marker=marker)


def test_verified_buffer_ignores_path_and_module_cache(root: Path) -> None:
    output, manifest = package(root)
    with patch.object(run_guest, "PR1170_SHA", manifest["pr1170_sha"]), patch.object(run_guest, "GUEST_SESSION_SHA256", manifest["inputs"]["guest_session.py"]), patch.object(run_guest, "commands", return_value=[]), patch.object(run_guest, "import_order", return_value=list(NAMES)), patch.object(run_guest, "assert_flat"), patch.object(run_guest, "assert_self"), patch.object(run_guest, "assert_pair"):
        (output / "manifest.json").write_text(json.dumps(manifest))
        _, verified = run_guest.fixture_identity(output)
    marker = root / "replacement-executed"
    attack = f"from pathlib import Path\nPath({str(marker)!r}).touch()\n".encode()
    (output / "source/pr1170/guest_session.py").write_bytes(attack)
    (output / "guest_session.py").write_bytes(attack)
    cache = output / "source/pr1170/__pycache__"
    cache.mkdir()
    (cache / "guest_session.pyc").write_bytes(attack)
    with patch.dict(sys.modules, {"mst_verified_guest_session": ModuleType("untrusted"), "guest_session": ModuleType("untrusted")}):
        loaded = LOAD_SESSION(output, verified)
    assert loaded.verified is True and not marker.exists()
    assert loaded.__file__ == str(output / "source/pr1170/guest_session.py")


def test_canonical_pin_and_retained_bootstrap(root: Path) -> None:
    _, canonical = canonical_source()
    output, manifest = package(root, canonical)
    assert (output / "source/pr1170/guest_session.py").read_bytes() == canonical
    preflight(output, manifest, should_reach=True)


def test_alternate_valid_commit_cannot_choose_trusted_pin(root: Path) -> None:
    output, original = package(root)
    repo = Path(original["pr1170_repo"])
    replacement = b"/* authored alternate source commit */\n"
    (repo / "tests/mst/main_func.c").write_bytes(replacement)
    git(repo, "add", "tests/mst/main_func.c")
    git(repo, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "test: different source identity")
    invalid = copy.deepcopy(original)
    invalid["pr1170_sha"] = git(repo, "rev-parse", "HEAD").decode().strip()
    (output / "source/pr1170/main_func.c").write_bytes(replacement)
    invalid["inputs"]["main_func.c"] = hashlib.sha256(replacement).hexdigest()
    invalid["files"]["source/pr1170/main_func.c"] = invalid["inputs"]["main_func.c"]
    preflight(output, invalid, should_reach=False, trusted=original)


def test_builder_rejects_unreviewed_pin_before_tools_or_lock(root: Path) -> None:
    arguments = ["build_guest.py", "--pr1170-repo", str(root), "--pr1170-sha", "0" * 40, "--fixture-repo", str(root), "--fixture-sha", "1" * 40, "--out", str(root / "out"), "--clang", "/absent/clang", "--ld", "/absent/ld", "--otool", "/absent/llvm-otool"]
    with patch.object(sys, "argv", arguments), patch.object(build_guest, "command") as command, patch.object(build_guest.fcntl, "flock") as lock, patch.object(build_guest.os, "access") as tool, redirect_stderr(io.StringIO()):
        try:
            build_guest.main()
        except SystemExit as error:
            assert error.code == 2
        else:
            raise AssertionError("builder accepted an unreviewed pin")
        command.assert_not_called()
        lock.assert_not_called()
        tool.assert_not_called()
    assert not (root / "out").exists()


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="mst-provenance-host-", dir="/tmp"))
    print(f"host source receipts retained: {root}")
    failures = 0
    for name, test in list(globals().items()):
        if name.startswith("test_"):
            case = root / name
            case.mkdir()
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
