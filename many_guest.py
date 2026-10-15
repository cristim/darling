"""Authored t8 generation and import-order checks, from vendored Mach-O headers.

Only called on this fixture package's own generated build output.
"""

from pathlib import Path
import struct


COUNT = 5000
NAMES = tuple(f"_mst_many_{index:04d}" for index in range(COUNT))


def generate(directory: Path) -> tuple[Path, Path]:
    directory.mkdir()
    library = directory / "libmany.c"
    main = directory / "main_many.c"
    library.write_text("".join(f"int {name[1:]} = 1;\n" for name in NAMES))
    main.write_text(
        "".join(f"extern volatile int {name[1:]};\n" for name in NAMES)
        + "int main(void) { int sum = 0;\n"
        + "".join(f"sum += {name[1:]};\n" for name in NAMES)
        + f"return sum == {COUNT} ? 23 : 24; }}\n"
    )
    return library, main


def uleb(data: bytes, offset: int, end: int) -> tuple[int, int]:
    value = 0
    for index in range(10):
        assert offset < end
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << (7 * index)
        if byte & 128 == 0:
            return value, offset
    raise AssertionError("oversized authored bind LEB")


def opcode_imports(data: bytes, *, lazy: bool = False) -> list[tuple[str, int, bool]]:
    offset, end = 0, len(data)
    symbol, ordinal, weak = "", 0, False
    result = []
    while offset < end:
        byte = data[offset]
        offset += 1
        opcode, immediate = byte & 0xF0, byte & 0x0F
        if opcode == 0:
            if not lazy:
                break
            continue
        if opcode == 0x10:
            ordinal = immediate
        elif opcode == 0x20:
            ordinal, offset = uleb(data, offset, end)
        elif opcode == 0x30:
            ordinal = immediate - 16 if immediate else 0
        elif opcode == 0x40:
            terminator = data.index(0, offset, end)
            symbol = data[offset:terminator].decode("ascii")
            weak = bool(immediate & 1)
            offset = terminator + 1
        elif opcode == 0x50:
            continue
        elif opcode in (0x60, 0x70, 0x80):
            _, offset = uleb(data, offset, end)
        elif opcode in (0x90, 0xA0, 0xB0):
            assert symbol
            result.append((symbol, ordinal, weak))
            if opcode == 0xA0:
                _, offset = uleb(data, offset, end)
        elif opcode == 0xC0:
            count, offset = uleb(data, offset, end)
            _, offset = uleb(data, offset, end)
            assert count <= 100000 and symbol
            result.extend([(symbol, ordinal, weak)] * count)
        else:
            raise AssertionError(f"unexpected authored bind opcode {opcode:#x}")
    return result


def chained_imports(data: bytes) -> list[tuple[str, int, bool]]:
    assert len(data) >= 28
    version, _, imports, symbols, count, form, compression = struct.unpack_from("<7I", data)
    assert version == 0 and compression == 0 and form in (1, 2, 3)
    stride = {1: 4, 2: 8, 3: 16}[form]
    assert 28 <= imports and imports + count * stride <= symbols <= len(data)
    result = []
    for index in range(count):
        value = struct.unpack_from("<Q" if form == 3 else "<I", data, imports + index * stride)[0]
        bits = 16 if form == 3 else 8
        ordinal = value & ((1 << bits) - 1)
        if ordinal >= 1 << (bits - 1):
            ordinal -= 1 << bits
        weak = bool(value & (1 << bits))
        name_offset = value >> (32 if form == 3 else 9)
        start = symbols + name_offset
        assert symbols <= start < len(data)
        end = data.index(0, start)
        result.append((data[start:end].decode("ascii"), ordinal, weak))
    return result


def import_details(path: Path, load_commands: list[tuple[int, int, int]], *, include_lazy: bool = True) -> tuple[list[str], list[tuple[str, int, bool]]]:
    data = path.read_bytes()
    libraries = []
    imports = []
    encodings = 0
    for kind, offset, size in load_commands:
        if kind in (0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            assert 24 <= name_offset < size
            end = data.index(0, offset + name_offset, offset + size)
            libraries.append(data[offset + name_offset:end].decode("ascii"))
        elif kind == 0x80000022:
            encodings += 1
            for field in (16, 32) if include_lazy else (16,):
                start, length = struct.unpack_from("<II", data, offset + field)
                assert start + length <= len(data)
                imports.extend(opcode_imports(data[start:start + length], lazy=field == 32))
        elif kind == 0x80000034:
            encodings += 1
            start, length = struct.unpack_from("<II", data, offset + 8)
            assert start + length <= len(data)
            imports.extend(chained_imports(data[start:start + length]))
    assert encodings == 1
    return libraries, imports


def import_order(path: Path, load_commands: list[tuple[int, int, int]]) -> list[str]:
    libraries, imports = import_details(path, load_commands)
    ordered = []
    for name, ordinal, weak in imports:
        if name.startswith("_mst_many_"):
            assert 0 < ordinal <= len(libraries) and libraries[ordinal - 1] == "@executable_path/libmst.dylib"
            assert not weak
            if name not in ordered:
                ordered.append(name)
    assert len(ordered) == COUNT and set(ordered) == set(NAMES)
    return ordered
