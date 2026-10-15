"""Two authored reexport graphs, using staged links and retained local terminals.

Recipes: dyld/tests/build-reexport-cycle.rb, pr2pre/reexport.py cycle, and
pr2pre/hostile.py trie_at_end. Encoding: vendored mach-o/loader.h export trie.
Never call this module on binaries outside this fixture builder's own output.
"""

from pathlib import Path
import shutil
import struct
from typing import Callable

from local_guest import export_terminals, mapped_target, trie_location
from many_guest import import_details, uleb


LAYOUT = {"cycle": ("libA.dylib", "libB.dylib"), "diamond": ("libR.dylib", "libB.dylib", "libC.dylib")}
LEAVES = {"cycle": ("libA.dylib", "_z", 71), "diamond": ("libB.dylib", "_y", 83)}
Decode = Callable[[bytes], list[tuple[int, int, int]]]
Invoke = Callable[[list[str]], bytes]


def encode(value: int) -> bytes:
    assert 0 <= value < 1 << 64
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    return bytes([*result, value])


def dylibs(path: Path, decode: Decode) -> tuple[str, list[tuple[str, int]]]:
    data = path.read_bytes()
    identities = []
    dependencies = []
    for kind, offset, size in decode(data):
        if kind not in (0xD, 0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20):
            continue
        name = struct.unpack_from("<I", data, offset + 8)[0]
        assert 24 <= name < size
        end = data.index(0, offset + name, offset + size)
        name = data[offset + name:end].decode("ascii")
        if kind == 0xD:
            identities.append(name)
        else:
            dependencies.append((name, kind))
    assert len(identities) == 1
    return identities[0], dependencies


def terminal(raw: bytes) -> tuple:
    flags, offset = uleb(raw, 0, len(raw))
    if flags == 8:
        ordinal, offset = uleb(raw, offset, len(raw))
        end = raw.index(0, offset)
        assert ordinal > 0 and end + 1 == len(raw)
        return "alias", ordinal, raw[offset:end].decode("ascii")
    assert flags == 0
    address, offset = uleb(raw, offset, len(raw))
    assert offset == len(raw)
    return "local", address


def trie(terms: dict[str, bytes]) -> bytes:
    names = sorted(terms)
    assert names and all(not other.startswith(name) for name in names for other in names if name != other)
    root_size = 2 + sum(len(name.encode("ascii")) + 2 for name in names)
    nodes = [encode(len(terms[name])) + terms[name] + b"\0" for name in names]
    assert root_size + sum(map(len, nodes)) < 128
    root = bytearray([0, len(names)])
    offset = root_size
    for name, node in zip(names, nodes):
        root += name.encode("ascii") + b"\0" + encode(offset)
        offset += len(node)
    assert len(root) == root_size
    return bytes(root) + b"".join(nodes)


def add_alias(path: Path, name: str, ordinal: int, imported: str, decode: Decode) -> None:
    original = path.read_bytes()
    commands = decode(original)
    before = export_terminals(path, commands)
    assert name not in before
    _, dependencies = dylibs(path, decode)
    assert 0 < ordinal <= len(dependencies)
    added = encode(8) + encode(ordinal) + imported.encode("ascii") + b"\0"
    blob = trie({**before, name: added})
    old_start, old_size, fields = trie_location(original, commands)
    linkedit = [offset for kind, offset, _ in commands if kind == 0x19 and original[offset + 8:offset + 24].rstrip(b"\0") == b"__LINKEDIT"]
    assert len(linkedit) == 1
    offset = linkedit[0]
    vmsize, fileoff, filesize = struct.unpack_from("<QQQ", original, offset + 32)
    assert fileoff + filesize == len(original) and filesize + len(blob) <= vmsize
    assert fileoff <= old_start and old_start + old_size <= len(original)
    for kind, command, _ in commands:
        if kind == 0x80000022:
            info = struct.unpack_from("<10I", original, command + 8)
            assert info[4] == info[5] == 0, "weak-bind stream not expected"
            ranges = [(info[i], info[i] + info[i + 1]) for i in (0, 2, 6, 8) if info[i + 1]]
            assert all(left[1] <= right[0] for left, right in zip(ranges, ranges[1:]))
    start = fileoff + vmsize - len(blob)
    assert start >= len(original)
    data = bytearray(original)
    data.extend(bytes(start - len(data)))
    data.extend(blob)
    struct.pack_into("<Q", data, offset + 48, vmsize)
    struct.pack_into("<II", data, fields, start, len(blob))
    expected = bytearray(original)
    expected[offset + 48:offset + 56] = data[offset + 48:offset + 56]
    expected[fields:fields + 8] = data[fields:fields + 8]
    assert data[:len(original)] == expected
    path.write_bytes(data)
    assert export_terminals(path, decode(data)) == {**before, name: added}


def assert_graph(directory: Path, kind: str, decode: Decode) -> list[tuple[str, str]]:
    images = {}
    for name in LAYOUT[kind]:
        path = directory / name
        identity, deps = dylibs(path, decode)
        assert identity == "@executable_path/" + name
        terms = export_terminals(path, decode(path.read_bytes()))
        images[name] = (path, deps, terms)
    if kind == "cycle":
        expected = {"libA.dylib": ["libB.dylib"], "libB.dylib": ["libA.dylib"]}
        assert terminal(images["libA.dylib"][2]["_x"]) == ("alias", 1, "_y")
        assert terminal(images["libB.dylib"][2]["_y"]) == ("alias", 1, "_z")
        wanted = [("libA.dylib", "_x"), ("libB.dylib", "_y"), ("libA.dylib", "_z")]
    else:
        expected = {"libR.dylib": ["libB.dylib", "libC.dylib"], "libB.dylib": [], "libC.dylib": ["libB.dylib"]}
        assert "_x" not in images["libR.dylib"][2] and "_x" not in images["libB.dylib"][2]
        assert terminal(images["libC.dylib"][2]["_x"]) == ("alias", 1, "_y")
        wanted = [("libR.dylib", "_x"), ("libB.dylib", "_x"), ("libC.dylib", "_x"), ("libB.dylib", "_y")]
    for name, deps in expected.items():
        assert images[name][1] == [("@executable_path/" + dep, 0x8000001F) for dep in deps]
    leaf_image, leaf_name, _ = LEAVES[kind]
    leaf = images[leaf_image]
    raw = leaf[2][leaf_name]
    value = terminal(raw)
    assert value[0] == "local"
    mapped_target(leaf[0].read_bytes(), decode(leaf[0].read_bytes()), value[1])
    original = directory.parent / "original" / leaf_image
    assert raw == export_terminals(original, decode(original.read_bytes()))[leaf_name]
    trace = []

    def walk(image: str, name: str, ancestors: tuple = ()) -> tuple | None:
        trace.append((image, name))
        assert (image, name) not in ancestors
        path, deps, terms = images[image]
        ancestry = (*ancestors, (image, name))
        if name in terms:
            entry = terminal(terms[name])
            if entry[0] == "local":
                mapped_target(path.read_bytes(), decode(path.read_bytes()), entry[1])
                return image, name, terms[name]
            assert 0 < entry[1] <= len(deps)
            return walk(Path(deps[entry[1] - 1][0]).name, entry[2] or name, ancestry)
        for dependency, command in deps:
            assert command == 0x8000001F
            found = walk(Path(dependency).name, name, ancestry)
            if found:
                return found
        return None

    assert walk(LAYOUT[kind][0], "_x") == (leaf_image, leaf_name, raw)
    assert trace == wanted, trace
    return trace


def assert_pair(root: Path, kind: str, decode: Decode) -> None:
    for mode in ("control", "missing"):
        directory = root / mode
        assert_graph(directory, kind, decode)
        main = directory / "main_alias"
        libraries, imports = import_details(main, decode(main.read_bytes()))
        nonlazy = import_details(main, decode(main.read_bytes()), include_lazy=False)[1]
        for symbol, library in (("_x", LAYOUT[kind][0]), ("_mst_alias_trigger", "libtrigger.dylib")):
            selected = [entry for entry in imports if entry[0] == symbol]
            assert len(selected) == 1 and not selected[0][2]
            ordinal = selected[0][1]
            assert 0 < ordinal <= len(libraries) and libraries[ordinal - 1] == "@executable_path/" + library
        assert any(name == "_mst_alias_trigger" and not weak for name, _, weak in nonlazy)
        provider = directory / "libtrigger.dylib"
        identity, deps = dylibs(provider, decode)
        assert identity == "@executable_path/libtrigger.dylib" and not deps
        terms = export_terminals(provider, decode(provider.read_bytes()))
        assert ("_mst_alias_trigger" in terms) == (mode == "control")
        if mode == "control":
            leaf = terminal(terms["_mst_alias_trigger"])
            assert leaf[0] == "local"
            mapped_target(provider.read_bytes(), decode(provider.read_bytes()), leaf[1])
    for name in (*LAYOUT[kind], "main_alias"):
        assert (root / "control" / name).read_bytes() == (root / "missing" / name).read_bytes()


def compile_sources(cc: list[str], obj: Path, sources: Path, invoke: Invoke) -> None:
    leaf = sources / "fx/alias_leaf.c"
    for name, symbol, value in (("alias_x", "x", 0), ("alias_z", "z", 71), ("alias_y", "y", 83)):
        invoke([*cc, "-c", str(leaf), f"-DALIAS_NAME={symbol}", f"-DALIAS_VALUE={value}", "-o", str(obj / f"{name}.o")])
    invoke([*cc, "-c", str(sources / "fx/alias_trigger.c"), "-o", str(obj / "alias_trigger.o")])
    for kind, (_, _, value) in LEAVES.items():
        invoke([*cc, "-c", str(sources / "fx/main_alias.c"), f"-DALIAS_EXPECT={value}", "-o", str(obj / f"main_alias_{kind}.o")])


def build(link: list[str], obj: Path, out: Path, invoke: Invoke, decode: Decode) -> None:
    out.mkdir()
    for kind in LAYOUT:
        root = out / kind
        stage, original, control, missing = (root / name for name in ("stage", "original", "control", "missing"))
        for directory in (stage, original, control, missing):
            directory.mkdir(parents=True)

        def library(path: Path, object_name: str, dependencies: tuple[Path, ...] = (), maps: tuple[Path, ...] = ()) -> None:
            arguments = [*link, "-dylib", "-install_name", "@executable_path/" + path.name, "-o", str(path), str(obj / object_name)]
            arguments += [argument for dependency in dependencies for argument in ("-reexport_library", str(dependency))]
            arguments += [argument for dependency in maps for argument in ("-dylib_file", "@executable_path/" + dependency.name + ":" + str(dependency))]
            invoke(arguments)

        entry = LAYOUT[kind][0]
        library(stage / entry, "alias_x.o")
        if kind == "cycle":
            library(stage / "libB.dylib", "libmstempty.o")
            library(control / "libA.dylib", "alias_z.o", (stage / "libB.dylib",), (stage / "libB.dylib",))
            library(control / "libB.dylib", "libmstempty.o", (control / "libA.dylib",), (stage / "libB.dylib", control / "libA.dylib"))
            shutil.copy2(control / "libA.dylib", original / "libA.dylib")
            add_alias(control / "libA.dylib", "_x", 1, "_y", decode)
            add_alias(control / "libB.dylib", "_y", 1, "_z", decode)
        else:
            library(control / "libB.dylib", "alias_y.o")
            library(control / "libC.dylib", "libmstempty.o", (control / "libB.dylib",), (control / "libB.dylib",))
            library(control / "libR.dylib", "libmstempty.o", (control / "libB.dylib", control / "libC.dylib"), (control / "libB.dylib", control / "libC.dylib"))
            add_alias(control / "libC.dylib", "_x", 1, "_y", decode)
            shutil.copy2(control / "libB.dylib", original / "libB.dylib")
        library(control / "libtrigger.dylib", "alias_trigger.o")
        invoke([*link, "-e", "_main", "-o", str(control / "main_alias"), str(obj / f"main_alias_{kind}.o"), str(stage / entry), str(control / "libtrigger.dylib"), str(obj / "libSystem.guest.dylib")])
        for name in (*LAYOUT[kind], "main_alias"):
            shutil.copy2(control / name, missing / name)
        library(missing / "libtrigger.dylib", "libmstempty.o")
        assert_pair(root, kind, decode)
