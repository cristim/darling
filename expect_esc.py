#!/usr/bin/env python3
"""Expected record for b_esc.bundle, and a check of the decoded name.

Usage: expect_esc.py line <from-path>   prints the expected JSON line
       expect_esc.py check <log-file>   exits 0 if the logged name decodes to the raw bytes
The escapes are assembled from chr(92) so no tool or shell along the way can expand them.
"""
import json
import sys

BS = chr(92)
RAW = b'_e"q' + bytes([92]) + b"b" + bytes([0x0A, 0x01, 0xFF, 0x7F, 0xC3, 0xA9]) + b"/" + b"Z" * 17


def escaped():
    out = ""
    for b in RAW:
        if b in (0x22, 0x5C):
            out += BS + chr(b)
        elif 0x20 <= b < 0x7F:
            out += chr(b)
        else:
            out += BS + "u00" + format(b, "02x")
    return out


def main():
    if sys.argv[1] == "line":
        rec = '{"v":1,"kind":"missing","sym":"%s","lib":"flat namespace","from":"%s","arch":"arm64"}'
        sys.stdout.write(rec % (escaped(), sys.argv[2]))
    else:
        got = json.loads(open(sys.argv[2], "rb").read())["sym"].encode("latin-1")
        sys.exit(0 if got == RAW else 1)


if __name__ == "__main__":
    main()
