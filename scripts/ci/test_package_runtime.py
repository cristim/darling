import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGER = Path(__file__).resolve().parent / "package_runtime.py"
LOCK_TOP = {"repos": [{"repo": "darling", "branch": "master", "base": "a" * 40, "prs": []}]}
LOCK_NESTED = {"vibedarling": [], "external_pinned": []}


class Merge(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def arch_dir(self, arch, payload=b"image", lie=False):
        d = self.root / "art" / f"runtime-{arch}"
        d.mkdir(parents=True)
        name = f"darling-runtime-v1-linux-{arch}.tar.zst"
        (d / name).write_bytes(payload)
        digest = "0" * 64 if lie else hashlib.sha256(payload).hexdigest()
        (d / f"fragment-{arch}.json").write_text(json.dumps({"file": name, "sha256": digest}))
        (d / "refs.lock.json").write_text(json.dumps(LOCK_TOP))
        (d / "nested.refs.lock.json").write_text(json.dumps(LOCK_NESTED))
        return d

    def merge(self, dirs):
        out = self.root / "manifest.json"
        cmd = [sys.executable, str(PACKAGER), "merge", "--version", "v1", "--repo", "VibeDarling/darling",
               "--sha", "b" * 40, "--published-at", "now", "--recipe-sha", "r", "--source-ref", "refs/heads/master",
               "--out", str(out), "--fragments", *[str(d / f"fragment-{d.name.removeprefix('runtime-')}.json") for d in dirs],
               "--lock-dirs", *map(str, dirs)]
        return subprocess.run(cmd, capture_output=True, text=True), out

    def test_manifest_carries_attestation_identity(self):
        done, out = self.merge([self.arch_dir("aarch64"), self.arch_dir("x86_64")])
        self.assertEqual(done.returncode, 0, done.stderr)
        manifest = json.loads(out.read_text())
        self.assertEqual(manifest["attestation"], {
            "signer_workflow": "VibeDarling/darling/.github/workflows/release-binaries.yml",
            "source_ref": "refs/heads/master", "deny_self_hosted_runners": True})
        self.assertEqual(manifest["build"]["recipe_sha256"], "r")

    def test_tampered_tarball_is_rejected(self):
        done, _ = self.merge([self.arch_dir("aarch64", lie=True)])
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("does not match its fragment sha256", done.stderr)

    def test_extra_tarball_is_rejected(self):
        d = self.arch_dir("aarch64")
        (d / "evil.tar.zst").write_bytes(b"x")
        done, _ = self.merge([d])
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("unexpected tarball", done.stderr)


if __name__ == "__main__":
    unittest.main()
