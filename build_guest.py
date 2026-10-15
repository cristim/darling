#!/usr/bin/env python3
"""Package authored arm64 fixtures from an explicit committed PR1170 tree.

Source-only authoring; execute only in an authorized heavy-build slot.
Mach-O fields below come from vendored cctools mach-o/loader.h and nlist.h.
Only files produced by this builder may be inspected or patched here.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

from many_guest import generate, import_order
from local_guest import assert_flat, patch_self
from alias_guest import build as build_aliases, compile_sources as compile_alias_sources


INPUTS = (
    "build.sh", "main_func.c", "main_data.c", "main_multi.c", "main_weak.c",
    "libmstreal.c", "libmstempty.c", "sysstub.c",
)
GUEST_INPUTS = ("build_guest.py", "run_guest.py", "many_guest.py", "fx/libguest.c", "fx/main_multi_weak.c", "fx/main_objc.c",
                "fx/main_dlopen.c", "fx/sysstub.c", "fx/bundle.c", "local_guest.py", "fx/guest_api.h", "fx/libthreadstub.c",
                "fx/main_threads.c", "fx/main_local.c", "fx/bundle_self.c", "alias_guest.py",
                "fx/main_alias.c", "fx/alias_leaf.c", "fx/alias_trigger.c")
CORE_PROGRAMS = ("main_multi", "main_weak", "main_multi_weak", "main_objc", "main_multi_oldsdk")
T8_PROGRAMS = ("main_many", "main_dlopen")
T8_BUNDLES = ("b_short", "b_long4095", "b_long4096")
T9_PROGRAMS = ("main_threads", "main_local")
T9_BUNDLES = ("b_thread_a", "b_thread_b", "b_self")


def command(argv: list[str], *, env: dict[str, str] | None = None) -> bytes:
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        stdout, stderr = process.communicate(timeout=300)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"build command exceeded deadline; process {process.pid} retained: {argv[0]}") from error
    if process.returncode:
        raise RuntimeError(f"command failed ({process.returncode}): {argv!r}\n{stderr.decode(errors='replace')}")
    return stdout


def absolute(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("path must be absolute")
    return path


def committed_inputs(repo: Path, sha: str, names: tuple[str, ...], prefix: str = "") -> dict[str, bytes]:
    assert re.fullmatch(r"[0-9a-f]{40}", sha), "exact source commit required"
    resolved = command(["git", "-C", str(repo), "rev-parse", sha + "^{commit}"]).decode().strip()
    assert resolved == sha
    result = {name: command(["git", "-C", str(repo), "show", f"{sha}:{prefix}{name}"]) for name in names}
    assert all(result.values()), "empty committed source input"
    return result


def retain_inputs(destination: Path, inputs: dict[str, bytes]) -> dict[str, str]:
    hashes = {}
    for name, data in inputs.items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as output:
            output.write(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    return hashes


def compile_guest(cc: list[str], sources: Path, obj: Path) -> None:
    for name in ("libguest", "main_multi_weak", "main_objc"):
        command([*cc, "-c", str(sources / "fx" / f"{name}.c"), "-o", str(obj / f"{name}.o")])


def commands(data: bytes) -> list[tuple[int, int, int]]:
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("expected authored little-endian Mach-O64")
    count, size = struct.unpack_from("<II", data, 16)
    end = 32 + size
    if end > len(data):
        raise ValueError("load commands exceed file")
    result = []
    offset = 32
    for _ in range(count):
        kind, length = struct.unpack_from("<II", data, offset)
        if length < 8 or offset + length > end:
            raise ValueError("invalid load command size")
        result.append((kind, offset, length))
        offset += length
    if offset != end:
        raise ValueError("load command size mismatch")
    return result


def assert_encoding(path: Path, variant: str) -> None:
    kinds = [kind for kind, _, _ in commands(path.read_bytes())]
    assert kinds.count(0x80000034) == int(variant == "chained"), path
    assert kinds.count(0x80000022) == int(variant == "opcode"), path


def sdk_probe(source: Path, target: Path) -> None:
    data = bytearray(source.read_bytes())
    versions = [(offset, size) for kind, offset, size in commands(data) if kind == 0x32]
    assert len(versions) == 1
    offset, size = versions[0]
    assert size >= 24
    platform, minos, sdk = struct.unpack_from("<III", data, offset + 8)
    assert (platform, minos, sdk) == (1, 0xB0000, 0xB0000)
    struct.pack_into("<I", data, offset + 16, 0xA0E00)
    assert struct.unpack_from("<III", data, offset + 8) == (1, 0xB0000, 0xA0E00)
    target.write_bytes(data)
    target.chmod(source.stat().st_mode & 0o777)


def assert_weak_import(path: Path) -> None:
    data = path.read_bytes()
    tables = [offset for kind, offset, _ in commands(data) if kind == 2]
    assert len(tables) == 1
    symoff, count, stroff, size = struct.unpack_from("<IIII", data, tables[0] + 8)
    assert symoff + 16 * count <= len(data) and stroff + size <= len(data)
    found = []
    for index in range(count):
        string, kind, _, desc, _ = struct.unpack_from("<IBBHQ", data, symoff + 16 * index)
        assert string < size
        name_end = data.index(0, stroff + string, stroff + size)
        name = data[stroff + string:name_end]
        if name == b"_f_weak":
            found.append((kind, desc))
    assert len(found) == 1 and found[0][0] & 0x0E == 0 and found[0][1] & 0x40, path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr1170-repo", type=absolute, required=True)
    parser.add_argument("--pr1170-sha", required=True)
    parser.add_argument("--fixture-repo", type=absolute, required=True)
    parser.add_argument("--fixture-sha", required=True)
    parser.add_argument("--out", type=absolute, required=True)
    parser.add_argument("--clang", type=absolute, required=True)
    parser.add_argument("--ld", type=absolute, required=True)
    parser.add_argument("--otool", type=absolute, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.pr1170_sha):
        parser.error("--pr1170-sha must name an exact committed tree")
    for path, name in ((args.clang, "clang"), (args.otool, "llvm-otool")):
        if path.name != name or not os.access(path, os.X_OK):
            parser.error(f"explicit executable must be named {name}: {path}")
    if not os.access(args.ld, os.X_OK):
        parser.error("--ld must be executable")
    lock_path = Path("/tmp/agent-locks/darling-heavy-build.lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock = lock_path.open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    inherited = committed_inputs(args.pr1170_repo, args.pr1170_sha, INPUTS, "tests/mst/")
    authored = committed_inputs(args.fixture_repo, args.fixture_sha, GUEST_INPUTS)
    assert authored["build_guest.py"] == Path(__file__).read_bytes(), "builder differs from committed fixture source"
    assert authored["many_guest.py"] == Path(__file__).with_name("many_guest.py").read_bytes(), "generator differs from committed fixture source"
    assert authored["local_guest.py"] == Path(__file__).with_name("local_guest.py").read_bytes(), "self metadata helper differs from committed fixture source"
    assert authored["alias_guest.py"] == Path(__file__).with_name("alias_guest.py").read_bytes(), "alias helper differs from committed fixture source"
    args.out.mkdir(mode=0o700)
    sources = args.out / "source/pr1170"
    guest_sources = args.out / "source/guest"
    provenance = retain_inputs(sources, inherited)
    guest_provenance = retain_inputs(guest_sources, authored)
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join((str(args.clang.parent), str(args.otool.parent), env.get("PATH", "")))
    env["MST_LD"] = str(args.ld)
    assert Path(shutil.which("clang", path=env["PATH"])) == args.clang
    assert Path(shutil.which("llvm-otool", path=env["PATH"])) == args.otool
    fixtures = args.out / "fixtures"
    command(["sh", str(sources / "build.sh"), str(fixtures), "arm64"], env=env)
    obj = fixtures / "arm64" / "obj"
    cc = [str(args.clang), "-target", "arm64-apple-macos11", "-ffreestanding", "-nostdinc", "-O1", "-fno-stack-protector"]
    compile_guest(cc, guest_sources, obj)
    compile_alias_sources(cc, obj, guest_sources, command)
    generated = args.out / "source/generated"
    many_library, many_main = generate(generated)
    for source, name in ((many_library, "libmany"), (many_main, "main_many"),
                         (guest_sources / "fx/main_dlopen.c", "main_dlopen"),
                         (guest_sources / "fx/sysstub.c", "guest_sysstub"),
                         *((guest_sources / "fx" / f"{name}.c", name) for name in ("libthreadstub", "main_threads", "main_local", "bundle_self"))):
        command([*cc, "-c", str(source), "-o", str(obj / f"{name}.o")])
    command([str(args.ld), "-arch", "arm64", "-dylib", "-platform_version", "macos", "11.0", "11.0",
             "-install_name", "/usr/lib/libSystem.B.dylib", "-compatibility_version", "1",
             "-o", str(obj / "libSystem.guest.dylib"), str(obj / "guest_sysstub.o"), str(obj / "libthreadstub.o")])
    many_imports = {}
    for variant in ("opcode", "chained"):
        flags = ["-fixup_chains"] if variant == "chained" else []
        link = [str(args.ld), "-arch", "arm64", "-platform_version", "macos", "11.0", "11.0", *flags]
        real = fixtures / "arm64" / variant / "real"
        empty = real.with_name("empty")
        library = real / "libmst.dylib"
        command([*link, "-dylib", "-install_name", "@executable_path/libmst.dylib", "-o", str(library), str(obj / "libmstreal.o"), str(obj / "libguest.o"), str(obj / "libmany.o")])
        for name in ("main_multi_weak", "main_objc", *T8_PROGRAMS):
            command([*link, "-e", "_main", "-o", str(real / name), str(obj / f"{name}.o"), str(library), str(obj / "libSystem.guest.dylib")])
            shutil.copyfile(real / name, empty / name)
            (empty / name).chmod(0o700)
        many_imports[variant] = import_order(real / "main_many", commands((real / "main_many").read_bytes()))
        bundles = real.parent / "bundles"
        bundles.mkdir()
        for name, symbol in (("b_short", "_mst_flat_missing"), ("b_long4095", "_" + "A" * 4094),
                             ("b_long4096", "_" + "A" * 4095), ("b_thread_a", "_mst_thread_a"), ("b_thread_b", "_mst_thread_b")):
            command([*cc, "-c", str(guest_sources / "fx/bundle.c"), f"-DMST_NAME={symbol}", "-o", str(obj / f"{name}.o")])
            bundle = bundles / f"{name}.bundle"
            command([*link, "-bundle", "-undefined", "dynamic_lookup", "-o", str(bundle), str(obj / f"{name}.o")])
            assert_encoding(bundle, variant)
            if name in ("b_thread_a", "b_thread_b"):
                assert_flat(bundle, commands(bundle.read_bytes()), symbol)
        self_bundle = bundles / "b_self.bundle"
        command([*link, "-bundle", "-undefined", "dynamic_lookup", "-o", str(self_bundle), str(obj / "bundle_self.o")])
        assert_encoding(self_bundle, variant)
        patch_self(self_bundle, commands(self_bundle.read_bytes()))
        for name in T9_PROGRAMS:
            command([*link, "-e", "_main", "-o", str(real / name), str(obj / f"{name}.o"), str(obj / "libSystem.guest.dylib")])
        aliases = real.parent / "aliases"
        build_aliases(link, obj, aliases, command, commands)
        for path in aliases.rglob("*"):
            if path.is_file():
                assert_encoding(path, variant)
        for directory in (real, empty):
            sdk_probe(directory / "main_multi", directory / "main_multi_oldsdk")
            for path in directory.iterdir():
                if path.name.startswith("main_") or path.suffix == ".dylib":
                    assert_encoding(path, variant)
            for name in ("main_weak", "main_multi_weak"):
                assert_weak_import(directory / name)
    files = {str(path.relative_to(args.out)): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in args.out.rglob("*") if path.is_file()}
    manifest = {"pr1170_repo": str(args.pr1170_repo), "pr1170_sha": args.pr1170_sha, "inputs": provenance,
                "fixture_repo": str(args.fixture_repo), "fixture_sha": args.fixture_sha,
                "fixture_inputs": guest_provenance, "many_imports": many_imports, "files": files}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
