#!/usr/bin/env python3
"""Host-only generated-input, authored metadata and cap-assertion probes."""

import json
from pathlib import Path
import struct
import sys
import tempfile

from build_guest import commands
from many_guest import COUNT, NAMES, generate, import_order, opcode_imports
from run_guest import GUEST_ROOT, assert_repeat_cap


def authored_metadata(root: Path, variant: str, names: tuple[str, ...] = NAMES, *, weak: bool = False,
                      ordinal: int = 1, done_prefix: bool = False) -> Path:
    library = b"@executable_path/libmst.dylib\0"
    size = (24 + len(library) + 7) & ~7
    dylib = struct.pack("<6I", 0xC, size, 24, 0, 0, 0) + library
    dylib += bytes(size - len(dylib))
    if variant == "opcode":
        stream = b"".join(bytes([0x10 | ordinal, 0x40 | int(weak)]) + name.encode() + b"\0\x90" for name in names) + b"\0"
        if done_prefix:
            stream = b"\0" + stream
        start = 32 + size + 48
        command = struct.pack("<12I", 0x80000022, 48, 0, 0, start, len(stream), 0, 0, 0, 0, 0, 0)
    else:
        pool = bytearray()
        table = bytearray()
        for name in names:
            table += struct.pack("<I", ordinal | (int(weak) << 8) | (len(pool) << 9))
            pool += name.encode() + b"\0"
        stream = struct.pack("<7I", 0, 0, 28, 28 + len(table), len(names), 1, 0) + table + pool
        command = struct.pack("<4I", 0x80000034, 16, 32 + size + 16, len(stream))
    header = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2, 2, size + len(command), 0, 0)
    path = root / f"{variant}-{len(names)}-{int(weak)}-{ordinal}.metadata"
    path.write_bytes(header + dylib + command + stream)
    return path


def test_generated_volatile_imports(root: Path) -> None:
    library, main = generate(root / "generated")
    definitions, source = library.read_text(), main.read_text()
    assert len(NAMES) == COUNT == 5000
    for name in NAMES:
        assert f"int {name[1:]} = 1;\n" in definitions
        assert f"extern volatile int {name[1:]};\n" in source
        assert f"sum += {name[1:]};\n" in source
    assert "return sum == 5000 ? 23 : 24" in source


def test_actual_import_order_and_rejections(root: Path) -> None:
    for variant in ("opcode", "chained"):
        names = tuple(reversed(NAMES))
        path = authored_metadata(root, variant, names)
        assert import_order(path, commands(path.read_bytes())) == list(names)
        for selected, weak, ordinal in ((NAMES[:-1], False, 1), (NAMES, True, 1), (NAMES, False, 2)):
            path = authored_metadata(root, variant, selected, weak=weak, ordinal=ordinal)
            try:
                import_order(path, commands(path.read_bytes()))
            except AssertionError:
                pass
            else:
                raise AssertionError("incomplete, weak or wrong-library data imports accepted")


def test_regular_done_stops_import_oracle(root: Path) -> None:
    path = authored_metadata(root, "opcode", done_prefix=True)
    try:
        import_order(path, commands(path.read_bytes()))
    except AssertionError:
        pass
    else:
        raise AssertionError("ordinary bind imports after DONE accepted")


def test_lazy_done_preserves_state_and_continues(root: Path) -> None:
    stream = b"\x11\x40_mst_many_0000\0\x90\0\x90"
    expected = ("_mst_many_0000", 1, False)
    assert opcode_imports(stream, lazy=True) == [expected, expected]
    assert opcode_imports(stream) == [expected]


def cap_input(symbol: str, bundle: Path, count: int) -> tuple[list[dict], bytes]:
    record = {"v": 1, "kind": "missing", "sym": symbol, "lib": "flat namespace", "from": GUEST_ROOT + str(bundle), "arch": "arm64"}
    final = {"v": 1, "kind": "truncated"}
    line = (json.dumps(record, separators=(",", ":")) + "\n").encode()
    raw = line * count + b'{"v":1,"kind":"truncated"}\n'
    return [record] * count + [final], raw


def test_record_and_byte_cap_contracts(root: Path) -> None:
    bundle = root / "bundle"
    records, raw = cap_input("_mst_flat_missing", bundle, 4096)
    assert_repeat_cap(records, raw, "_mst_flat_missing", bundle, byte_cap=False)
    long_name = "_" + "A" * 4094
    _, one = cap_input(long_name, bundle, 1)
    final_size = len(b'{"v":1,"kind":"truncated"}\n')
    count = (16 * 1024 * 1024 - final_size) // (len(one) - final_size)
    records, raw = cap_input(long_name, bundle, count)
    assert_repeat_cap(records, raw, long_name, bundle, byte_cap=True)
    for invalid in (records[:-1], [{"v": 1, "kind": "truncated", "reason": "scan_budget"}], [*records[:-1], {"v": 1, "kind": "scan_skipped"}]):
        try:
            assert_repeat_cap(invalid, raw, long_name, bundle, byte_cap=True)
        except AssertionError:
            pass
        else:
            raise AssertionError("missing cap or unexpected closed kind accepted")


def test_reserved_terminal_space_at_byte_boundary(root: Path) -> None:
    bundle = Path("/tmp/pppppppppppppppppppp/fixtures/arm64/opcode/bundles/b_long4095.bundle")
    symbol = "_" + "A" * 4094
    final = b'{"v":1,"kind":"truncated"}\n'
    skipped = b'{"v":1,"kind":"scan_skipped"}\n'
    _, one = cap_input(symbol, bundle, 1)
    row_size = len(one) - len(final)
    reserve = len(final) + len(skipped)
    count = (16 * 1024 * 1024 - reserve) // row_size
    records, raw = cap_input(symbol, bundle, count)
    assert count == 3929 and row_size == 4269
    assert len(raw) + row_size <= 16 * 1024 * 1024
    assert_repeat_cap(records, raw, symbol, bundle, byte_cap=True)
    for wrong_count in (count - 1, count + 1):
        records, raw = cap_input(symbol, bundle, wrong_count)
        try:
            assert_repeat_cap(records, raw, symbol, bundle, byte_cap=True)
        except AssertionError:
            pass
        else:
            raise AssertionError("premature or over-reserve byte-cap count accepted")


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="mst-many-host-", dir="/tmp"))
    print(f"host t8 inputs retained: {root}")
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
