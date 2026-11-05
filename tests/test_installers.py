"""Isolated public-interface installer regressions; no network or real installs."""
import hashlib
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.dest = self.root / "bin"
        self.stage = self.root / "tmp"
        self.release = self.root / "release"
        for directory in (self.home, self.dest, self.stage, self.release):
            directory.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        GENTLE_CC_DEST=str(self.dest), TMPDIR=str(self.stage))
        for key in ("GENTLE_CC_SOURCE", "GENTLE_CC_REF", "GENTLE_CC_VERSION"):
            self.env.pop(key, None)
        arch = {"x86_64": "amd64", "amd64": "amd64",
                "aarch64": "arm64", "arm64": "arm64"}[platform.machine().lower()]
        self.asset = f"gentle-ai-cc_4.3.1-cc.1_{platform.system().lower()}_{arch}"
        self.binary = b"new binary\n"
        self.wrapper = b"new wrapper\n"
        (self.release / self.asset).write_bytes(self.binary)
        (self.release / "gentle-cc").write_bytes(self.wrapper)
        self.manifest()
        for name in ("gentle-ai-cc", "gentle-cc"):
            path = self.dest / name
            path.write_bytes(("old " + name).encode())
            path.chmod(0o640)
        self.before = self.snapshot()

    def manifest(self, wrapper=True):
        names = [self.asset] + (["gentle-cc"] if wrapper else [])
        (self.release / "checksums.txt").write_text("".join(
            f"{hashlib.sha256((self.release / name).read_bytes()).hexdigest()}  {name}\n"
            for name in names))

    def snapshot(self):
        return {p.name: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
                for p in self.dest.iterdir()}

    def run_release(self, *args):
        return subprocess.run(["bash", str(ROOT / "gentle-cc-install.sh"),
                               "--from-release", self.release.as_uri(), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_validation_failures_preserve_both_destinations(self):
        for failure in ("wrapper mismatch", "wrapper missing", "wrapper entry missing",
                        "binary mismatch", "binary entry missing"):
            with self.subTest(failure=failure):
                for name, (data, mode) in self.before.items():
                    (self.dest / name).write_bytes(data)
                    (self.dest / name).chmod(mode)
                (self.release / self.asset).write_bytes(self.binary)
                (self.release / "gentle-cc").write_bytes(self.wrapper)
                self.manifest()
                if failure == "wrapper mismatch":
                    (self.release / "gentle-cc").write_bytes(b"tampered")
                elif failure == "wrapper missing":
                    (self.release / "gentle-cc").unlink()
                elif failure == "wrapper entry missing":
                    self.manifest(wrapper=False)
                elif failure == "binary mismatch":
                    (self.release / self.asset).write_bytes(b"tampered")
                else:
                    (self.release / "checksums.txt").write_text("")
                result = self.run_release()
                self.assertEqual(result.returncode, 1, result)
                message = {"wrapper mismatch": "checksum mismatch for gentle-cc:",
                           "wrapper missing": "wrapper download failed",
                           "wrapper entry missing": "no checksum entry for gentle-cc",
                           "binary mismatch": f"checksum mismatch for {self.asset}:",
                           "binary entry missing": f"no checksum entry for {self.asset}"}[failure]
                if failure.endswith("entry missing"):
                    # Existing verifier exits on grep's nonzero status under pipefail.
                    self.assertEqual(result.stderr, "")
                else:
                    self.assertIn(message, result.stderr)
                self.assertNotIn("installed:", result.stdout)
                self.assertEqual(self.snapshot(), self.before)
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_success_installs_both_executable_artifacts(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stderr, "")
        self.assertIn(f"installed: {self.dest}/gentle-ai-cc\n", result.stdout)
        self.assertIn("next:\n", result.stdout)
        for name, data in (("gentle-ai-cc", self.binary), ("gentle-cc", self.wrapper)):
            self.assertEqual((self.dest / name).read_bytes(), data)
            self.assertTrue((self.dest / name).stat().st_mode & stat.S_IXUSR)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_no_wrapper_does_not_request_wrapper_and_sha_only_still_installs(self):
        (self.release / "gentle-cc").unlink()
        self.manifest(wrapper=False)
        result = self.run_release("--no-wrapper", "--sha-only")
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stderr, "")
        self.assertNotIn("downloading gentle-cc", result.stdout)
        self.assertNotIn("next:", result.stdout)
        self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
        self.assertEqual(self.snapshot()["gentle-cc"], self.before["gentle-cc"])
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_authenticated_child_status_output_and_cleanup(self):
        checkout = self.root / "checkout"
        checkout.mkdir()
        shutil.copy2(ROOT / "install.sh", checkout / "install.sh")
        child = checkout / "gentle-cc-install.sh"
        child.write_text('#!/bin/bash\nprintf "child stdout\\n"\nprintf "child stderr\\n" >&2\nexit "$CHILD_STATUS"\n')
        child.chmod(0o755)
        fakebin = self.root / "fakebin"
        fakebin.mkdir()
        gh = fakebin / "gh"
        gh.write_text('#!/bin/bash\nexit 0\n')
        gh.chmod(0o755)
        self.env["PATH"] = str(fakebin) + os.pathsep + os.environ["PATH"]
        self.env["GENTLE_CC_OWNER_REPO"] = "fixture/repo"
        for status in (0, 37):
            with self.subTest(status=status):
                self.env["CHILD_STATUS"] = str(status)
                result = subprocess.run(["bash", str(checkout / "install.sh")],
                                        env=self.env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, status, result)
                self.assertEqual(result.stdout, "downloading release 4.3.1-cc.1 from fixture/repo via gh ...\nchild stdout\n")
                self.assertEqual(result.stderr, "child stderr\n")
                self.assertEqual(list(self.stage.iterdir()), [])


class PowerShellInstallerTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pwsh") or shutil.which("powershell"),
                         "PowerShell runtime unavailable")
    def test_windows_installer_fixtures(self):
        runner = shutil.which("pwsh") or shutil.which("powershell")
        result = subprocess.run([runner, "-NoProfile", "-File", str(ROOT / "tests/installers.ps1")],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result)


if __name__ == "__main__":
    unittest.main()
