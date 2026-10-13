#!/usr/bin/env python3
"""Replace a placeholder symbol name in an authored Mach-O with hostile bytes of the same length.

Usage: patch_name.py <file> <placeholder>
The replacement holds a quote, a backslash, a newline, 0x01, 0xFF, 0x7F and a UTF-8 'e acute',
padded with 'Z'. Every occurrence (string table and bind opcodes) is patched, so offsets do not move.
"""
import sys

HOSTILE = b'_e"q\\b\n\x01\xff\x7f\xc3\xa9/'


def main():
    path, placeholder = sys.argv[1], sys.argv[2].encode()
    new = HOSTILE + b"Z" * (len(placeholder) - len(HOSTILE))
    assert len(new) == len(placeholder)
    data = open(path, "rb").read()
    count = data.count(placeholder)
    if count < 2:
        sys.exit(f"expected the placeholder in the string table and the bind info, found {count}")
    open(path, "wb").write(data.replace(placeholder, new))


if __name__ == "__main__":
    main()
