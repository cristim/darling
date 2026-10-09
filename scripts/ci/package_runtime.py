#!/usr/bin/env python3
"""Package a DESTDIR runtime image and build the release manifest.

  package_runtime.py fragment --image DIR --version V --arch A --out DIR [--run-url U]
  package_runtime.py merge --version V --repo OWNER/NAME --sha SHA --fragments DIR... --out FILE
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = "usr/local"
NATIVE = "usr/local/libexec/darling/usr/lib/native"
HOST_ELF_DIRS = ("usr/local/bin", "usr/local/libexec/darling/bin", "usr/local/libexec/darling/usr/libexec/darling")
SONAME = re.compile(rb"lib[A-Za-z0-9_+-]+\.so(?:\.[0-9]+)+")
GLIBC = re.compile(r"GLIBC_([0-9]+(?:\.[0-9]+)*)")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


ALLOWED_APPS = {"usr/local/libexec/darling/Applications/Darling Applications.app"}


def clean_room_check(image):
    top = {p.name for p in image.iterdir()}
    if top != {"usr"} or {p.name for p in (image / "usr").iterdir()} != {"local"}:
        raise SystemExit(f"error: image must contain only usr/local, found {sorted(top)}")
    for path in image.rglob("*"):
        rel = path.relative_to(image)
        if any(p.endswith(".dSYM") for p in rel.parts):
            raise SystemExit(f"error: forbidden path in image: {rel}")
        if path.name.endswith(".app") and rel.as_posix() not in ALLOWED_APPS:
            raise SystemExit(f"error: app bundle not on the allow-list (Darling-built only): {rel}")


def wrapped_sonames(image):
    found = set()
    for dylib in sorted((image / NATIVE).glob("*.dylib")):
        found.update(m.decode() for m in SONAME.findall(dylib.read_bytes()))
    return sorted(found)


def glibc_minimum(image):
    best = (0,)
    for directory in HOST_ELF_DIRS:
        for path in sorted((image / directory).glob("*")) if (image / directory).is_dir() else []:
            if path.is_symlink() or not path.is_file() or path.read_bytes()[:4] != b"\x7fELF":
                continue
            out = subprocess.run(["objdump", "-T", str(path)], capture_output=True, text=True).stdout
            for version in GLIBC.findall(out):
                best = max(best, tuple(int(x) for x in version.split(".")))
    return ".".join(map(str, best)) if best != (0,) else None


def unpacked_size(image):
    return sum(p.lstat().st_size for p in image.rglob("*") if p.is_file() and not p.is_symlink())


def fragment(args):
    image, out = Path(args.image).resolve(), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    clean_room_check(image)
    name = f"darling-runtime-{args.version}-linux-{args.arch}.tar.zst"
    tarball = out / name
    tar = subprocess.Popen(
        ["tar", "--create", "--sort=name", "--owner=0", "--group=0", "--numeric-owner",
         "--mode=u-s,g-s,go-w", "--directory", str(image), "usr"], stdout=subprocess.PIPE)
    with open(tarball, "wb") as sink:
        zstd = subprocess.run(["zstd", "-19", "-T0", "-q"], stdin=tar.stdout, stdout=sink)
    if tar.wait() or zstd.returncode:
        raise SystemExit("error: tar|zstd failed")
    entry = {
        "file": name, "sha256": sha256(tarball), "size": tarball.stat().st_size,
        "unpacked_size": unpacked_size(image), "install_root": ROOT,
        "launcher": f"{ROOT}/bin/darling",
        "host_requires": {"glibc": glibc_minimum(image), "wrapped_sonames": wrapped_sonames(image)},
    }
    (out / f"fragment-{args.arch}.json").write_text(json.dumps(entry, indent=2) + "\n")
    print(json.dumps(entry, indent=2))


def comparable(lock):
    return sorted((r["repo"], r.get("branch"), r["base"], tuple(r["paths"])) for r in lock["repos"])


def merge(args):
    base = f"https://github.com/{args.repo}/releases/download/{args.version}"
    artifacts = {}
    for path in args.fragments:
        arch = Path(path).stem.removeprefix("fragment-")
        entry = json.loads(Path(path).read_text())
        entry["url"] = f"{base}/{entry['file']}"
        artifacts[arch] = entry
    if not artifacts:
        raise SystemExit("error: no architecture produced an image")
    locks = {}
    for kind in ("refs", "nested.refs"):
        sets = [comparable(json.loads(Path(d, f"{kind}.lock.json").read_text())) for d in args.lock_dirs]
        if any(s != sets[0] for s in sets):
            raise SystemExit(f"error: {kind} lock differs between architectures; re-run the workflow")
        for d in args.lock_dirs:
            for item in json.loads(Path(d, f"{kind}.lock.json").read_text())["repos"]:
                if item.get("prs"):
                    raise SystemExit(f"error: {kind} lock contains PRs for {item['repo']}")
        locks[kind] = f"{kind}.lock.json"
    manifest = {
        "schema": 1, "version": args.version, "prerelease": args.prerelease,
        "published_at": args.published_at,
        "source": {"repo": args.repo, "sha": args.sha},
        "artifacts": artifacts, "locks": list(locks.values()),
        "build": {"run_url": args.run_url, "builder": args.builder},
    }
    Path(args.out).write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fragment")
    f.add_argument("--image", required=True); f.add_argument("--version", required=True)
    f.add_argument("--arch", required=True); f.add_argument("--out", required=True)
    m = sub.add_parser("merge")
    m.add_argument("--version", required=True); m.add_argument("--repo", required=True)
    m.add_argument("--sha", required=True); m.add_argument("--out", required=True)
    m.add_argument("--fragments", nargs="+", required=True)
    m.add_argument("--lock-dirs", nargs="+", required=True)
    m.add_argument("--prerelease", action="store_true")
    m.add_argument("--published-at", required=True)
    m.add_argument("--run-url", default="")
    m.add_argument("--builder", default="")
    args = parser.parse_args()
    {"fragment": fragment, "merge": merge}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
