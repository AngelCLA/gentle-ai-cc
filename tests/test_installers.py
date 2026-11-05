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

    def source_fixture(self, *, wrapper=True, external_wrapper=False):
        distribution = self.root / "distribution with spaces"
        distribution.mkdir()
        installer = distribution / "gentle-cc-install.sh"
        shutil.copy2(ROOT / "gentle-cc-install.sh", installer)
        if wrapper:
            shutil.copy2(ROOT / "gentle-cc", distribution / "gentle-cc")
        checkout = self.root / "external module with spaces"
        checkout.mkdir()
        if external_wrapper:
            (checkout / "gentle-cc").write_bytes(b"unrelated external wrapper\n")
        fakebin = self.root / "fake tools"
        fakebin.mkdir()
        tools = {
            "git": '''#!/bin/bash
printf 'git %s\n' "$1" >> "$TOOL_LOG"
case "$1" in
  clone)
    mkdir -p "$4"
    if [ -f "$FIXTURE_SOURCE/gentle-cc" ]; then
      cp "$FIXTURE_SOURCE/gentle-cc" "$4/gentle-cc"
    fi
    if [ "${CHANGE_DISTRIBUTION:-0}" = 1 ]; then
      printf 'changed during clone\n' > "$FIXTURE_DISTRIBUTION/gentle-cc"
    fi
    ;;
  checkout) ;;
  *) exit 90 ;;
esac
''',
            "go": '''#!/bin/bash
printf 'go %s\n' "$1" >> "$TOOL_LOG"
[ "$1" = build ] || exit 91
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    printf 'new binary\n' > "$2"
    exit 0
  fi
  shift
done
exit 92
''',
        }
        for name, script in tools.items():
            path = fakebin / name
            path.write_text(script)
            path.chmod(0o755)
        self.tool_log = self.root / "tool log"
        self.env.update(PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
                        TOOL_LOG=str(self.tool_log), FIXTURE_SOURCE=str(checkout),
                        FIXTURE_DISTRIBUTION=str(distribution))
        return installer, checkout

    def run_source(self, installer, checkout, *args):
        # Invoke from outside the distribution so sibling lookup cannot use cwd.
        return subprocess.run(["bash", str(installer), "--from-source", str(checkout),
                               "--ref", "fixture-ref", *args], cwd=self.home,
                              env=self.env, capture_output=True, text=True, timeout=10)

    def source_stdout(self, checkout, *, guidance=True):
        output = (f"platform: {platform.system().lower()}/{self.asset.split('_')[-1]}  "
                  f"asset: {self.asset}\n"
                  f"cloning {checkout} ...\n"
                  "building at fixture-ref (reproducible) ...\n"
                  f"built SHA256: {hashlib.sha256(self.binary).hexdigest()}\n"
                  f"installed: {self.dest}/gentle-ai-cc\n")
        if guidance:
            output += (f"\nnext:\n  {self.dest}/gentle-ai-cc version\n"
                       f"  {self.dest}/gentle-cc install --preset full-gentleman"
                       f"   # or: {self.dest}/gentle-cc sync\n")
        return output

    def test_source_installs_distribution_wrapper_not_external_module_wrapper(self):
        installer, checkout = self.source_fixture(external_wrapper=True)
        expected_wrapper = (installer.parent / "gentle-cc").read_bytes()
        # The distribution artifact must already be staged when cloning starts.
        self.env["CHANGE_DISTRIBUTION"] = "1"
        result = self.run_source(installer, checkout)
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stdout, self.source_stdout(checkout))
        self.assertEqual(result.stderr, "")
        self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
        self.assertEqual((self.dest / "gentle-cc").read_bytes(), expected_wrapper)
        for name in ("gentle-ai-cc", "gentle-cc"):
            self.assertTrue((self.dest / name).stat().st_mode & stat.S_IXUSR)
        self.assertEqual(self.tool_log.read_text(), "git clone\ngit checkout\ngo build\n")
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_source_without_external_wrapper_installs_distribution_wrapper(self):
        installer, checkout = self.source_fixture()
        (self.dest / "gentle-cc").unlink()
        result = self.run_source(installer, checkout)
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stdout, self.source_stdout(checkout))
        self.assertEqual(result.stderr, "")
        self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
        self.assertEqual((self.dest / "gentle-cc").read_bytes(),
                         (installer.parent / "gentle-cc").read_bytes())
        self.assertTrue((self.dest / "gentle-cc").stat().st_mode & stat.S_IXUSR)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_source_missing_distribution_wrapper_fails_without_destination_changes(self):
        installer, checkout = self.source_fixture(wrapper=False, external_wrapper=True)
        for existing_destination in (True, False):
            with self.subTest(existing_destination=existing_destination):
                if not existing_destination:
                    self.dest = self.root / "not created destination"
                    self.env["GENTLE_CC_DEST"] = str(self.dest)
                result = self.run_source(installer, checkout)
                self.assertEqual(result.returncode, 1, result)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr,
                                 f"install: source wrapper unavailable: {installer.parent}/gentle-cc\n")
                if existing_destination:
                    self.assertEqual(self.snapshot(), self.before)
                else:
                    self.assertFalse(self.dest.exists())
                self.assertFalse(self.tool_log.exists())
                self.assertEqual(list(self.stage.iterdir()), [])

    def test_source_no_wrapper_works_without_distribution_wrapper(self):
        installer, checkout = self.source_fixture(wrapper=False, external_wrapper=True)
        for existing_wrapper in (True, False):
            with self.subTest(existing_wrapper=existing_wrapper):
                if not existing_wrapper:
                    (self.dest / "gentle-cc").unlink()
                result = self.run_source(installer, checkout, "--no-wrapper", "--sha-only")
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stdout, self.source_stdout(checkout, guidance=False))
                self.assertEqual(result.stderr, "")
                self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
                self.assertTrue((self.dest / "gentle-ai-cc").stat().st_mode & stat.S_IXUSR)
                if existing_wrapper:
                    self.assertEqual(self.snapshot()["gentle-cc"], self.before["gentle-cc"])
                else:
                    self.assertFalse((self.dest / "gentle-cc").exists())
                self.assertEqual(list(self.stage.iterdir()), [])

    def publication_faults(self):
        """Intercept only publication tools, inside this fixture's private PATH."""
        fakebin = self.root / "publication tools"
        fakebin.mkdir()
        for tool in ("cp", "chmod", "mv", "mktemp", "rm"):
            real = shutil.which(tool)
            script = fakebin / tool
            script.write_text(f'''#!/bin/bash
if [ "{tool}" = rm ] && [ "$*" = "-f $GENTLE_CC_DEST/gentle-ai-cc" ] &&
   [ "${{FAIL_RESTORE:-0}}" = 1 ]; then
  exit 74
fi
case "$*" in
  *"$GENTLE_CC_DEST/.gentle-cc-install."*)
    kind=""
    case "{tool}:$*" in
      mktemp:*) kind=stage-directory ;;
      cp:*"/new-"*) kind=stage ;;
      cp:*"/old-"*) kind=snapshot ;;
      chmod:*) kind=permissions ;;
      mv:*"/old-"*) kind=restore ;;
      mv:*) kind=rename ;;
    esac
    if [ "$kind" = "$FAIL_KIND" ]; then
      count=0
      [ ! -f "$FAIL_COUNT" ] || read -r count < "$FAIL_COUNT"
      count=$((count + 1))
      printf '%s\\n' "$count" > "$FAIL_COUNT"
      [ "$count" != "$FAIL_AT" ] || exit 73
    fi
    if [ "$kind" = restore ] && [ "${{FAIL_RESTORE:-0}}" = 1 ]; then
      exit 74
    fi
    ;;
esac
exec "{real}" "$@"
''')
            script.chmod(0o755)
        self.env["PATH"] = str(fakebin) + os.pathsep + self.env["PATH"]
        self.env["FAIL_COUNT"] = str(self.root / "failure count")

    def release_prefix(self, *, no_wrapper=False):
        output = (f"platform: {platform.system().lower()}/{self.asset.split('_')[-1]}  "
                  f"asset: {self.asset}\n"
                  f"downloading {self.asset} ...\n"
                  f"checksum OK ({self.asset}): {hashlib.sha256(self.binary).hexdigest()}\n")
        if not no_wrapper:
            output += ("downloading gentle-cc wrapper ...\n"
                       f"checksum OK (gentle-cc): {hashlib.sha256(self.wrapper).hexdigest()}\n")
        return output

    def test_publication_failures_restore_only_requested_artifacts(self):
        for mode in ("release", "source"):
            for existing in (True, False):
                for no_wrapper in (False, True):
                    cases = [("stage-directory", 1, "cannot create publication staging"),
                             ("stage", 1, "cannot stage gentle-ai-cc"),
                             ("permissions", 1, "cannot set permissions for gentle-ai-cc"),
                             ("rename", 1, "cannot replace gentle-ai-cc")]
                    if existing:
                        cases.append(("snapshot", 1, "cannot snapshot gentle-ai-cc"))
                    if not no_wrapper:
                        cases += [(kind, 2, message) for kind, message in (
                            ("stage", "cannot stage gentle-cc"),
                            ("permissions", "cannot set permissions for gentle-cc"),
                            ("rename", "cannot replace gentle-cc"))]
                        if existing:
                            cases.append(("snapshot", 2, "cannot snapshot gentle-cc"))
                    for kind, occurrence, message in cases:
                        with self.subTest(mode=mode, existing=existing,
                                          no_wrapper=no_wrapper, kind=kind, at=occurrence):
                            # Each injected failure has its own private filesystem and PATH.
                            fixture = InstallerTests()
                            fixture.setUp()
                            try:
                                if not existing:
                                    (fixture.dest / "gentle-ai-cc").unlink()
                                    if not no_wrapper:
                                        (fixture.dest / "gentle-cc").unlink()
                                (fixture.dest / "unrelated").write_bytes(b"keep me")
                                (fixture.dest / "unrelated").chmod(0o604)
                                before = fixture.snapshot()
                                if mode == "source":
                                    installer, checkout = fixture.source_fixture()
                                fixture.publication_faults()
                                fixture.env.update(FAIL_KIND=kind, FAIL_AT=str(occurrence))
                                args = ["--no-wrapper"] if no_wrapper else []
                                if mode == "release":
                                    result = fixture.run_release(*args)
                                    prefix = fixture.release_prefix(no_wrapper=no_wrapper)
                                else:
                                    result = fixture.run_source(installer, checkout, *args)
                                    prefix = fixture.source_stdout(checkout).split("built SHA256:")[0]
                                self.assertEqual(result.returncode, 1, result)
                                self.assertEqual(result.stdout, prefix)
                                self.assertEqual(result.stderr, f"install: {message}\n")
                                self.assertEqual(fixture.snapshot(), before)
                                self.assertEqual(list(fixture.stage.iterdir()), [])
                            finally:
                                fixture.doCleanups()

    def test_restoration_failure_reports_and_retains_backup(self):
        self.publication_faults()
        self.env.update(FAIL_KIND="rename", FAIL_AT="2", FAIL_RESTORE="1")
        result = self.run_release()
        self.assertEqual(result.returncode, 1, result)
        self.assertEqual(result.stdout, self.release_prefix())
        recovery, = self.dest.glob(".gentle-cc-install.*")
        self.assertEqual(result.stderr,
                         f"install: restoration failed for {self.dest}/gentle-ai-cc\n"
                         f"install: backups retained at {recovery}; manual recovery required\n"
                         "install: cannot replace gentle-cc\n")
        self.assertEqual((recovery / "old-gentle-ai-cc").read_bytes(),
                         self.before["gentle-ai-cc"][0])
        self.assertEqual(stat.S_IMODE((recovery / "old-gentle-ai-cc").stat().st_mode), 0o640)
        self.assertEqual(self.snapshot_artifact("gentle-cc"), self.before["gentle-cc"])
        self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_new_artifact_removal_failure_is_explicit_in_source_mode(self):
        (self.dest / "gentle-ai-cc").unlink()
        (self.dest / "unrelated").write_bytes(b"unchanged")
        (self.dest / "unrelated").chmod(0o600)
        unrelated = self.snapshot_artifact("unrelated")
        installer, checkout = self.source_fixture()
        self.publication_faults()
        self.env.update(FAIL_KIND="rename", FAIL_AT="2", FAIL_RESTORE="1")
        result = self.run_source(installer, checkout)
        self.assertEqual(result.returncode, 1, result)
        self.assertEqual(result.stdout, self.source_stdout(checkout).split("built SHA256:")[0])
        recovery, = self.dest.glob(".gentle-cc-install.*")
        self.assertEqual(result.stderr,
                         f"install: restoration failed for {self.dest}/gentle-ai-cc\n"
                         f"install: backups retained at {recovery}; manual recovery required\n"
                         "install: cannot replace gentle-cc\n")
        self.assertFalse((recovery / "old-gentle-ai-cc").exists())
        self.assertEqual((self.dest / "gentle-ai-cc").read_bytes(), self.binary)
        self.assertEqual(self.snapshot_artifact("gentle-cc"), self.before["gentle-cc"])
        self.assertEqual(self.snapshot_artifact("unrelated"), unrelated)
        self.assertEqual(list(self.stage.iterdir()), [])

    def snapshot_artifact(self, name):
        path = self.dest / name
        return path.read_bytes(), stat.S_IMODE(path.stat().st_mode)

    def test_unsafe_destinations_rejected_before_publication(self):
        for kind in ("symlink", "directory"):
            with self.subTest(kind=kind):
                path = self.dest / "gentle-cc"
                path.unlink() if path.is_symlink() or path.is_file() else path.rmdir()
                target = self.root / "symlink target"
                target.write_bytes(b"do not follow")
                if kind == "symlink":
                    path.symlink_to(target)
                else:
                    path.mkdir()
                result = self.run_release()
                self.assertEqual(result.returncode, 1, result)
                self.assertEqual(result.stdout, self.release_prefix())
                self.assertEqual(result.stderr, f"install: unsafe destination: {path}\n")
                self.assertEqual(self.snapshot_artifact("gentle-ai-cc"), self.before["gentle-ai-cc"])
                self.assertEqual(target.read_bytes(), b"do not follow")
                self.assertEqual(list(self.dest.glob(".gentle-cc-install.*")), [])

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
