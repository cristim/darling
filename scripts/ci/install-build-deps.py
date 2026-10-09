#!/usr/bin/env python3
"""Install debian/control Build-Depends on the current host without mk-build-deps.

Needed because the list names multilib packages that do not exist on aarch64.
"""
import platform
import re
import subprocess
import sys

MULTILIB_ONLY = {"libc6-dev-i386", "gcc-multilib"}


def available(package):
    result = subprocess.run(["apt-cache", "show", package], capture_output=True, text=True)
    return result.returncode == 0 and bool(result.stdout.strip())


def main():
    control = sys.argv[1] if len(sys.argv) > 1 else "debian/control"
    text = open(control, encoding="utf-8").read()
    field = re.search(r"^Build-Depends:(.*?)(?=^\S)", text, re.S | re.M).group(1)
    arm = platform.machine() in ("aarch64", "arm64")
    packages = []
    for group in field.replace("\n", " ").split(","):
        alternatives = [re.sub(r"[\s(\[].*", "", alt.strip()) for alt in group.split("|") if alt.strip()]
        alternatives = [a for a in alternatives if not (arm and a in MULTILIB_ONLY)]
        if not alternatives:
            continue
        chosen = next((a for a in alternatives if available(a)), None)
        if chosen is None:
            raise SystemExit(f"error: none of {alternatives} is installable")
        packages.append(chosen)
    packages = sorted(set(packages))
    print("installing:", " ".join(packages))
    subprocess.run(["sudo", "apt-get", "install", "-y", "--no-install-recommends", *packages], check=True)


if __name__ == "__main__":
    main()
