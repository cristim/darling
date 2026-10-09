#!/usr/bin/env python3
"""Compare the builder locks of two runs.

  lock_diff.py refresh-nested --builder SCRIPT --lock OLD_NESTED --output NEW_NESTED
  lock_diff.py diff --old DIR --new DIR --markdown FILE [--force] [--github-output FILE]

DIR holds refs.lock.json and nested.refs.lock.json. `diff` decides whether a build is needed
(build=true/false) and writes the changed module SHAs as a markdown table.
"""
import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from package_runtime import comparable  # noqa: E402

KINDS = ("refs", "nested.refs")


def load_builder(path):
    spec = importlib.util.spec_from_file_location("lock_builder", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refresh_nested(args):
    """Re-resolve the branch heads of the repos in a nested lock, without checking anything out.

    The set of nested repos only changes when a top-level module changes, which the top lock shows.
    """
    builder = load_builder(args.builder)
    lock = json.loads(Path(args.lock).read_text())
    lock["vibedarling"] = [builder.remote_refs(copy.deepcopy(item)) for item in lock["vibedarling"]]
    Path(args.output).write_text(json.dumps(lock, indent=2) + "\n")


def read(directory, kind):
    path = Path(directory, f"{kind}.lock.json")
    return comparable(json.loads(path.read_text())) if path.is_file() else None


def changes(old, new):
    """Rows (repo, branch, old shas, new shas) for every (repo, branch) whose SHAs differ."""
    removed, added = set(old) - set(new), set(new) - set(old)
    keys = {(r, b) for r, b, _ in removed | added}
    return [(r, b or "", sorted(s for rr, bb, s in removed if (rr, bb) == (r, b)),
             sorted(s for rr, bb, s in added if (rr, bb) == (r, b))) for r, b in sorted(keys, key=str)]


def short(shas):
    return ", ".join(s[:12] for s in shas) or "(none)"


def markdown(rows, reason):
    lines = [reason, ""]
    if rows:
        lines += ["| module | branch | previous | current |", "|---|---|---|---|"]
        lines += [f"| {r} | {b} | {short(o)} | {short(n)} |" for r, b, o, n in rows]
    return "\n".join(lines) + "\n"


def diff(args):
    old = {k: read(args.old, k) for k in KINDS}
    new = {k: read(args.new, k) for k in KINDS}
    if any(v is None for v in new.values()):
        raise SystemExit("error: current locks are incomplete")
    first = any(v is None for v in old.values())
    rows = [] if first else [row for k in KINDS for row in changes(old[k], new[k])]
    if first:
        reason, build = "No previous release locks: first build.", True
    elif rows:
        reason, build = f"{len(rows)} module(s) changed since the previous release.", True
    elif args.force:
        reason, build = "Nothing changed since the previous release; build forced.", True
    else:
        reason, build = "Nothing changed since the previous release.", False
    Path(args.markdown).write_text(markdown(rows, reason))
    print(reason)
    if args.github_output:
        with open(args.github_output, "a") as handle:
            handle.write(f"build={'true' if build else 'false'}\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("refresh-nested")
    r.add_argument("--builder", required=True); r.add_argument("--lock", required=True)
    r.add_argument("--output", required=True)
    d = sub.add_parser("diff")
    d.add_argument("--old", required=True); d.add_argument("--new", required=True)
    d.add_argument("--markdown", required=True); d.add_argument("--force", action="store_true")
    d.add_argument("--github-output")
    args = parser.parse_args()
    {"refresh-nested": refresh_nested, "diff": diff}[args.cmd](args)


if __name__ == "__main__":
    main()
