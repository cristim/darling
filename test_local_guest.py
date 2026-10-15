#!/usr/bin/env python3
"""Host-only authored metadata and fake thread/local guest-contract probes."""

import json
from pathlib import Path
import struct
import sys
import tempfile

from build_guest import commands
from local_guest import assert_self, exports, patch_self
from run_guest import GUEST_ROOT, run_t9


def leb(value: int) -> bytes:
    output = bytearray()
    while value >= 128:
        output.append((value & 127) | 128)
        value >>= 7
    output.append(value)
    return bytes(output)


def metadata(root: Path, variant: str, *, ordinal: int = -2, have_address: int = 64, flags: int = 0) -> Path:
    edges = (b"_mst_self_have\0", b"_bundle_entry\0")
    first = leb(2 + len(leb(have_address)) - 1) + leb(flags) + leb(have_address) + b"\0"
    second = b"\x02\0\x50\0"
    root_size = 2 + sum(len(edge) + 1 for edge in edges)
    trie = b"\0\x02" + edges[0] + leb(root_size) + edges[1] + leb(root_size + len(first)) + first + second
    segment = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__TEXT", 0, 0x1000, 0, 0, 7, 5, 0, 0)
    old = b"_mst_self_need\0"
    if variant == "opcode":
        start = 32 + 72 + 48
        bindings = bytes([0x30 | (ordinal & 15), 0x40]) + old + b"\x90\0"
        binding_command = struct.pack("<12I", 0x80000022, 48, 0, 0, start, len(bindings), 0, 0, 0, 0, start + len(bindings), len(trie))
        load_commands = segment + binding_command
    else:
        start = 32 + 72 + 16 + 16
        bindings = struct.pack("<7I", 0, 0, 28, 32, 1, 1, 0) + struct.pack("<I", ordinal & 255) + old
        binding_command = struct.pack("<4I", 0x80000034, 16, start, len(bindings))
        load_commands = segment + binding_command + struct.pack("<4I", 0x80000033, 16, start + len(bindings), len(trie))
    header = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 8, 2 if variant == "opcode" else 3, len(load_commands), 0, 0)
    path = root / f"{variant}-{ordinal}-{have_address}-{flags}.metadata"
    path.write_bytes(header + load_commands + bindings + trie + old)
    return path


def test_self_flat_patch_preserves_local_targets(root: Path) -> None:
    for variant in ("opcode", "chained"):
        path = metadata(root, variant)
        load_commands = commands(path.read_bytes())
        before = exports(path, load_commands)
        assert before == {"_mst_self_have": 64, "_bundle_entry": 80}
        patch_self(path, load_commands)
        assert_self(path, load_commands)
        assert exports(path, load_commands) == before
        assert b"_mst_self_need\0" not in path.read_bytes()
        for ordinal, address, flags in ((-1, 64, 0), (-2, 0x1800, 0), (-2, 64, 8)):
            invalid = metadata(root, variant, ordinal=ordinal, have_address=address, flags=flags)
            try:
                patch_self(invalid, commands(invalid.read_bytes()))
            except AssertionError:
                pass
            else:
                raise AssertionError("non-flat or nonlocal/unmapped export accepted")


class FakePrefix:
    def __init__(self, root: Path, failure: str = ""):
        self.root = root
        self.failure = failure
        self.tags = []

    def guest(self, tag: str, program: str, variables: list[str], *, program_arguments: tuple[str, ...]) -> tuple[int, bytes, bytes]:
        self.tags.append(tag)
        directory = Path(next(value.split("=", 1)[1] for value in variables if value.startswith("DARLING_MISSING_SYMBOLS_LOG=")).removeprefix(GUEST_ROOT))
        local = "-local-" in tag
        paths = (program_arguments[1],) if local else program_arguments[:2]
        errors = [f"dlopen({path}, 6): Symbol not found: _mst_thread_{name}\n  Referenced from: {path}\n  Expected in: flat namespace\n" for name, path in zip(("a", "b"), paths)]
        if local:
            output = "self-entry=42\nseparate-miss-complete\n" + errors[0] + "\nself-retained=42\n"
        else:
            output = "thread-a-complete\n" + errors[0] + "\nthread-b-complete\n" + errors[1] + "\n"
        if self.failure == "wrong-error":
            output = output.replace("Symbol not found: _mst_thread_a\n", "Symbol not found: _unrelated\n")
        elif self.failure == "missing-completion":
            output = output.replace("thread-b-complete\n", "")
        if "DARLING_MISSING_SYMBOLS=log" in variables:
            rows = [{"v": 1, "kind": "missing", "sym": f"_mst_thread_{name}", "lib": "flat namespace", "from": path, "arch": "arm64"} for name, path in zip(("a", "b"), paths)]
            if self.failure == "wrong-log":
                rows[0]["sym"] = "_unrelated"
            elif local and self.failure == "self-false-positive":
                rows.append({**rows[0], "sym": "_mst_self_have"})
            log = directory / f"{Path(program).name}-1-{len(self.tags)}.jsonl"
            log.write_text("".join(json.dumps(row) + "\n" for row in rows))
            log.chmod(0o600)
        return 0, output.encode(), b""


def test_thread_local_controller_contracts(root: Path) -> None:
    valid = root / "valid"
    valid.mkdir()
    prefix = FakePrefix(valid)
    results = run_t9(prefix, root / "package", "fix")
    assert len(results) == len(prefix.tags) == len(set(prefix.tags)) == 88
    assert len([tag for tag in prefix.tags if "concurrent-" in tag and tag.endswith("-on")]) == 40
    for failure in ("wrong-error", "missing-completion", "wrong-log", "self-false-positive"):
        case = root / failure
        case.mkdir()
        try:
            run_t9(FakePrefix(case, failure), root / "package", "fix")
        except AssertionError:
            pass
        else:
            raise AssertionError(f"guest-contract corruption accepted: {failure}")


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="mst-local-host-", dir="/tmp"))
    print(f"host thread/local receipts retained: {root}")
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
