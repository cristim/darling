"""Validate and patch only the authored self-flat bundle's interface metadata."""

from pathlib import Path
import struct

from many_guest import import_details, uleb


def trie_location(data: bytes, load_commands: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    tries = []
    for kind, offset, size in load_commands:
        if kind == 0x80000033:
            tries.append((*struct.unpack_from("<II", data, offset + 8), offset + 8))
        elif kind == 0x80000022:
            start, length = struct.unpack_from("<II", data, offset + 40)
            if length:
                tries.append((start, length, offset + 40))
    assert len(tries) == 1
    start, length, field = tries[0]
    assert length > 0 and start + length <= len(data)
    return start, length, field


def mapped_target(data: bytes, load_commands: list[tuple[int, int, int]], address: int) -> None:
    segments = []
    for kind, offset, size in load_commands:
        if kind == 0x19:
            assert size >= 72
            start, length = struct.unpack_from("<QQ", data, offset + 24)
            if length:
                segments.append((start, start + length))
    assert segments
    base = min(low for low, _ in segments)
    assert any(low <= base + address < high for low, high in segments)


def export_terminals(path: Path, load_commands: list[tuple[int, int, int]]) -> dict[str, bytes]:
    data = path.read_bytes()
    start, length, _ = trie_location(data, load_commands)
    trie = data[start:start + length]
    stack = [(0, "", ())]
    result = {}
    visits = 0
    while stack:
        offset, prefix, ancestors = stack.pop()
        visits += 1
        assert visits <= 1024 and offset not in ancestors and 0 <= offset < len(trie)
        node = offset
        terminal_size, offset = uleb(trie, offset, len(trie))
        terminal_end = offset + terminal_size
        assert terminal_end < len(trie)
        if terminal_size:
            assert prefix not in result
            result[prefix] = trie[offset:terminal_end]
        children = trie[terminal_end]
        offset = terminal_end + 1
        for _ in range(children):
            end = trie.index(0, offset)
            edge = trie[offset:end].decode("ascii")
            assert edge
            child, offset = uleb(trie, end + 1, len(trie))
            stack.append((child, prefix + edge, (*ancestors, node)))
    return result


def exports(path: Path, load_commands: list[tuple[int, int, int]]) -> dict[str, int]:
    result = {}
    for name, terminal in export_terminals(path, load_commands).items():
        flags, offset = uleb(terminal, 0, len(terminal))
        assert flags == 0, "expected a genuine local regular export"
        address, offset = uleb(terminal, offset, len(terminal))
        assert offset == len(terminal)
        mapped_target(path.read_bytes(), load_commands, address)
        result[name] = address
    return result


def assert_flat(path: Path, load_commands: list[tuple[int, int, int]], symbol: str) -> None:
    _, imports = import_details(path, load_commands)
    assert imports == [(symbol, -2, False)], imports


def assert_self(path: Path, load_commands: list[tuple[int, int, int]]) -> None:
    assert_flat(path, load_commands, "_mst_self_have")
    assert set(exports(path, load_commands)) == {"_mst_self_have", "_bundle_entry"}


def patch_self(path: Path, load_commands: list[tuple[int, int, int]]) -> None:
    assert_flat(path, load_commands, "_mst_self_need")
    before = exports(path, load_commands)
    assert set(before) == {"_mst_self_have", "_bundle_entry"}
    data = path.read_bytes()
    old, new = b"_mst_self_need\0", b"_mst_self_have\0"
    assert len(old) == len(new) and data.count(old) == 2
    path.write_bytes(data.replace(old, new))
    assert_self(path, load_commands)
    assert exports(path, load_commands) == before
