#!/usr/bin/env python3
"""Host-only provenance preflight tests with a fresh authored Git repository."""

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

import build_guest
import run_guest
from alias_guest import LAYOUT, LEAVES, compile_sources as compile_alias_sources
from many_guest import NAMES


GUEST_INPUTS = build_guest.GUEST_INPUTS
PROGRAMS = ("main_multi", "main_weak", "main_multi_weak", "main_objc", "main_multi_oldsdk", "main_many", "main_dlopen", "libmst.dylib")


class ExecutionReached(Exception):
    pass


def git(repo: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *arguments], stderr=subprocess.STDOUT, timeout=10)


def package(root: Path) -> tuple[Path, dict]:
    repo = root / "repo"
    repo.mkdir()
    git(repo, "init", "--quiet")
    for name in build_guest.INPUTS:
        path = repo / "tests/mst" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"/* authored fixture input: {name} */\n")
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
        for name in ("main_threads", "main_local"):
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


def preflight(package_path: Path, manifest: dict, *, should_reach: bool) -> None:
    (package_path / "manifest.json").write_text(json.dumps(manifest))
    arguments = ["run_guest.py", "--launcher", sys.executable, "--base-receipt", "/tmp/base-receipt", "--fix-receipt", "/tmp/fix-receipt", "--package", str(package_path)]
    reached = False
    with patch.object(sys, "argv", arguments), patch.object(run_guest, "runtime_identity", return_value={}), patch.object(run_guest.fcntl, "flock", side_effect=ExecutionReached), patch.object(run_guest, "commands", return_value=[]), patch.object(run_guest, "import_order", return_value=list(NAMES)), patch.object(run_guest, "assert_flat"), patch.object(run_guest, "assert_self"), patch.object(run_guest, "assert_pair"):
        try:
            run_guest.main()
        except ExecutionReached:
            reached = True
        except (AssertionError, ValueError, KeyError, TypeError):
            pass
    assert reached == should_reach, "invalid package reached execution boundary" if reached else "valid package rejected"


def test_empty_and_partial_files(root: Path) -> None:
    output, original = package(root)
    preflight(output, original, should_reach=True)
    invalid = copy.deepcopy(original)
    invalid["files"] = {}
    preflight(output, invalid, should_reach=False)
    for required in ("fixtures/arm64/opcode/empty/main_multi", "fixtures/arm64/chained/real/libmst.dylib", "source/guest/fx/main_objc.c",
                     "fixtures/arm64/chained/empty/main_many", "fixtures/arm64/opcode/bundles/b_long4095.bundle"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False)
    for required in ("fixtures/arm64/opcode/real/main_threads", "fixtures/arm64/chained/bundles/b_self.bundle"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False)
    for required in ("fixtures/arm64/opcode/aliases/cycle/missing/main_alias", "fixtures/arm64/chained/aliases/diamond/control/libC.dylib",
                     "fixtures/arm64/opcode/aliases/cycle/original/libA.dylib"):
        invalid = copy.deepcopy(original)
        del invalid["files"][required]
        preflight(output, invalid, should_reach=False)


def test_invalid_digest_and_source_metadata(root: Path) -> None:
    output, original = package(root)
    for field, value in (("inputs", {}), ("fixture_inputs", {}), ("fixture_sha", "bad")):
        invalid = copy.deepcopy(original)
        invalid[field] = value
        preflight(output, invalid, should_reach=False)
    invalid = copy.deepcopy(original)
    invalid["files"]["fixtures/arm64/opcode/empty/main_multi"] = 5
    preflight(output, invalid, should_reach=False)
    invalid = copy.deepcopy(original)
    invalid["inputs"]["main_multi.c"] = "0" * 64
    preflight(output, invalid, should_reach=False)


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
    assert set(invoked) == {"libguest.c", "main_multi_weak.c", "main_objc.c"}
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
    preflight(output, invalid, should_reach=False)
    source.write_bytes(git(Path(original["fixture_repo"]), "show", f"{original['fixture_sha']}:fx/main_objc.c"))
    with patch.object(run_guest, "digest", wraps=run_guest.digest) as digest:
        digest.side_effect = lambda path: "0" * 64 if path == Path(run_guest.__file__).with_name("run_guest.py") else hashlib.sha256(path.read_bytes()).hexdigest()
        preflight(output, original, should_reach=False)


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
