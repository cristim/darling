#!/usr/bin/env python3
"""Host-only alias metadata/controller probes. No compiler or guest code executes."""

import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile

from alias_guest import LAYOUT, add_alias, assert_graph, assert_pair
from build_guest import commands
from local_guest import export_terminals
from run_guest import GUEST_ROOT, run_aliases


def dylib_command(kind: int, name: str) -> bytes:
    string = name.encode() + b"\0"
    size = (24 + len(string) + 7) & ~7
    return struct.pack("<6I", kind, size, 24, 0, 0, 0) + string + bytes(size - 24 - len(string))


def image(path: Path, variant: str, dependencies: tuple[str, ...] = (), *, symbol: str = "_pad", address: int = 64, main: bool = False, lazy_trigger: bool = False) -> None:
    # One local terminal, encoded independently of the alias trie writer.
    edge = symbol.encode() + b"\0"
    original_trie = b"\0\x01" + edge + bytes([3 + len(edge)]) + b"\x02\0" + bytes([address]) + b"\0"
    prefix = dylib_command(0xD, "@executable_path/" + path.name)
    prefix += b"".join(dylib_command(0xC if main else 0x8000001F, "@executable_path/" + name) for name in dependencies)
    ordinary = b"\x12\x40_mst_alias_trigger\0\x90\0" if main and not lazy_trigger else b""
    lazy = (b"\x12\x40_mst_alias_trigger\0\x90\0" if lazy_trigger else b"") + (b"\x11\x40_x\0\x90\0" if main else b"")
    fileoff = 0x400
    if variant == "opcode":
        blobs = ordinary + lazy + original_trie
        info = struct.pack("<12I", 0x80000022, 48, 0, 0, fileoff if ordinary else 0, len(ordinary), 0, 0,
                           fileoff + len(ordinary) if lazy else 0, len(lazy), fileoff + len(ordinary) + len(lazy), len(original_trie))
    else:
        pool = b"_x\0_mst_alias_trigger\0" if main else b""
        table = struct.pack("<II", 1, 2 | (3 << 9)) if main else b""
        chain = struct.pack("<7I", 0, 0, 28, 28 + len(table), 2 if main else 0, 1, 0) + table + pool
        blobs = chain + original_trie
        info = struct.pack("<4I", 0x80000034, 16, fileoff, len(chain)) + struct.pack("<4I", 0x80000033, 16, fileoff + len(chain), len(original_trie))
    text = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__TEXT", 0x1000, 0x1000, 0, fileoff, 7, 5, 0, 0)
    linkedit = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__LINKEDIT", 0x2000, 0x1000, fileoff, len(blobs), 7, 1, 0, 0)
    load = text + linkedit + prefix + info
    count = 4 + len(dependencies) + int(variant == "chained")
    header = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2 if main else 6, count, len(load), 0, 0)
    assert len(header + load) <= fileoff
    path.write_bytes(header + load + bytes(fileoff - len(header + load)) + blobs)


def graph(root: Path, kind: str, variant: str) -> None:
    control, missing, original = (root / name for name in ("control", "missing", "original"))
    for directory in (control, missing, original):
        directory.mkdir(parents=True)
    if kind == "cycle":
        image(control / "libA.dylib", variant, ("libB.dylib",), symbol="_z")
        image(control / "libB.dylib", variant, ("libA.dylib",))
        shutil.copy2(control / "libA.dylib", original / "libA.dylib")
        add_alias(control / "libA.dylib", "_x", 1, "_y", commands)
        add_alias(control / "libB.dylib", "_y", 1, "_z", commands)
    else:
        image(control / "libB.dylib", variant, symbol="_y")
        image(control / "libC.dylib", variant, ("libB.dylib",))
        image(control / "libR.dylib", variant, ("libB.dylib", "libC.dylib"))
        shutil.copy2(control / "libB.dylib", original / "libB.dylib")
        add_alias(control / "libC.dylib", "_x", 1, "_y", commands)
    image(control / "libtrigger.dylib", variant, symbol="_mst_alias_trigger")
    image(control / "main_alias", variant, (LAYOUT[kind][0], "libtrigger.dylib"), main=True)
    for name in (*LAYOUT[kind], "main_alias"):
        shutil.copy2(control / name, missing / name)
    image(missing / "libtrigger.dylib", variant)


def test_exact_graphs_and_preserved_leaf(root: Path) -> None:
    expected = {
        "cycle": [("libA.dylib", "_x"), ("libB.dylib", "_y"), ("libA.dylib", "_z")],
        "diamond": [("libR.dylib", "_x"), ("libB.dylib", "_x"), ("libC.dylib", "_x"), ("libB.dylib", "_y")],
    }
    for variant in ("opcode", "chained"):
        for kind in LAYOUT:
            case = root / variant / kind
            graph(case, kind, variant)
            assert_pair(case, kind, commands)
            assert assert_graph(case / "control", kind, commands) == expected[kind]
            if kind == "cycle":
                a = case / "control/libA.dylib"
                assert export_terminals(a, commands(a.read_bytes())) == {"_z": b"\0\x40", "_x": b"\x08\x01_y\0"}
                b = case / "control/libB.dylib"
                assert export_terminals(b, commands(b.read_bytes()))["_y"] == b"\x08\x01_z\0"


def test_wrong_order_and_alias_names_rejected(root: Path) -> None:
    for failure in ("order", "alias", "leaf", "lazy-trigger"):
        case = root / failure
        graph(case, "diamond", "opcode")
        if failure == "order":
            for mode in ("control", "missing"):
                image(case / mode / "libR.dylib", "opcode", ("libC.dylib", "libB.dylib"))
        elif failure == "alias":
            for mode in ("control", "missing"):
                path = case / mode / "libC.dylib"
                data = path.read_bytes()
                assert data.count(b"\x08\x01_y\0") == 1
                path.write_bytes(data.replace(b"\x08\x01_y\0", b"\x08\x01_q\0"))
        elif failure == "leaf":
            for mode in ("control", "missing"):
                image(case / mode / "libB.dylib", "opcode", symbol="_y", address=80)
        else:
            for mode in ("control", "missing"):
                image(case / mode / "main_alias", "opcode", ("libR.dylib", "libtrigger.dylib"), main=True, lazy_trigger=True)
        try:
            assert_pair(case, "diamond", commands)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"incorrect graph/proof accepted: {failure}")


def test_linkedit_assumptions_fail_before_patch(root: Path) -> None:
    for failure in ("weak", "space"):
        path = root / f"{failure}.metadata"
        image(path, "opcode", ("libB.dylib",), symbol="_z")
        data = bytearray(path.read_bytes())
        if failure == "weak":
            offset = next(offset for kind, offset, _ in commands(data) if kind == 0x80000022)
            struct.pack_into("<II", data, offset + 24, 0x400, 1)
        else:
            offset = next(offset for kind, offset, _ in commands(data) if kind == 0x19 and data[offset + 8:offset + 24].rstrip(b"\0") == b"__LINKEDIT")
            struct.pack_into("<Q", data, offset + 32, len(data) - 0x400)
        path.write_bytes(data)
        before = path.read_bytes()
        try:
            add_alias(path, "_x", 1, "_y", commands)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"unsupported LINKEDIT shape patched: {failure}")
        assert path.read_bytes() == before


class FakePrefix:
    def __init__(self, root: Path, failure: str = ""):
        self.root, self.failure = root, failure
        self.tags = []

    def guest(self, tag: str, program: str, variables: list[str]) -> tuple[int, bytes, bytes]:
        self.tags.append(tag)
        executable = Path(program.removeprefix(GUEST_ROOT))
        control = executable.parent.name == "control"
        result = (0, b"alias-control-complete\n", b"") if control else (1, b"", b"Symbol not found: _mst_alias_trigger\n")
        if control and self.failure == "no-control-call":
            result = (0, b"", b"")
        if not control and self.failure == "wrong-trigger":
            result = (1, b"", b"Symbol not found: _unrelated\n")
        if not control and "DARLING_MISSING_SYMBOLS=log" in variables:
            directory = Path(next(value.split("=", 1)[1] for value in variables if value.startswith("DARLING_MISSING_SYMBOLS_LOG=")).removeprefix(GUEST_ROOT))
            rows = [{"v": 1, "kind": "missing", "sym": "_mst_alias_trigger", "lib": GUEST_ROOT + str(executable.parent / "libtrigger.dylib"), "from": program, "arch": "arm64"}]
            if self.failure == "alias-false-positive":
                rows.append({**rows[0], "sym": "_x"})
            if self.failure == "wrong-provider":
                rows[0]["lib"] = "flat namespace"
            log = directory / f"main_alias-1-{len(self.tags)}.jsonl"
            log.write_text("".join(json.dumps(row) + "\n" for row in rows))
            log.chmod(0o600)
        return result


def test_controller_requires_control_and_exact_missing_set(root: Path) -> None:
    valid = root / "valid"
    valid.mkdir()
    prefix = FakePrefix(valid)
    assert len(run_aliases(prefix, root / "package", "fix")) == 16
    assert len(prefix.tags) == len(set(prefix.tags)) == 16
    for failure in ("no-control-call", "wrong-trigger", "alias-false-positive", "wrong-provider"):
        case = root / failure
        case.mkdir()
        try:
            run_aliases(FakePrefix(case, failure), root / "package", "fix")
        except AssertionError:
            pass
        else:
            raise AssertionError(f"invalid alias outcome accepted: {failure}")


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="mst-alias-host-", dir="/tmp"))
    print(f"host alias receipts retained: {root}")
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
