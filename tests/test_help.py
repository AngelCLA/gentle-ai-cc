"""Public help checks only: no installation, build, or release access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HelpTests(unittest.TestCase):
    def run_help(self, script, *options):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            sentinel = home / "keep"
            sentinel.write_bytes(b"unchanged\n")
            env = {"HOME": temporary, "TMPDIR": temporary,
                   "PATH": os.defpath, "LC_ALL": "C"}
            result = subprocess.run(["bash", script, *options, "--help"],
                                    cwd=ROOT, env=env, capture_output=True,
                                    text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(result.stderr, "")
            self.assertEqual(sorted(p.name for p in home.iterdir()), ["keep"])
            self.assertEqual(sentinel.read_bytes(), b"unchanged\n")
            return result.stdout

    def test_wrapper_help_spacing_and_existing_guidance(self):
        output = self.run_help("gentle-cc")
        for row in (
            "  gentle-cc build            Build the companion binary from your branch",
            "  gentle-cc sync    [args]   Sync only Command Code (companion)",
            "  gentle-cc install [args]   Install only Command Code (companion)",
            "  gentle-cc doctor  [args]   Run doctor with the companion binary",
            "  gentle-cc sync-all [args]  Official sync for other agents + Command Code",
            "Mutating install/sync/sync-all require Python 3 fcntl.flock (Linux/macOS).",
            "The persistent OS lock file must never be removed, even when idle.",
            "  GENTLE_CC_BIN    companion binary path  (default ~/.local/bin/gentle-ai-cc)",
        ):
            self.assertIn(row + "\n", output)
        self.assertNotIn("sync-all[args]", output)

    def test_installer_help_options_and_existing_modes(self):
        output = self.run_help("gentle-cc-install.sh")
        for row in (
            "#   --from-release URL_PREFIX",
            "#   --from-source GIT_URL [--ref REF]",
            "#       The pinned source currently requires Go 1.25.10 or newer.",
            "#   ~/.local/bin/gentle-ai-cc     (companion binary)",
            "#   ~/.local/bin/gentle-cc        (wrapper, unless --no-wrapper)",
            "#   --ref REF       Source commit/tag (default the pinned commit).",
            "#   --version V     Release asset version / source build version (default 4.3.1-cc.1).",
            "#   --no-wrapper    Install only the binary; leave any existing wrapper unchanged.",
            "#   --sha-only      Still installs; suppresses final next-step guidance only.",
        ):
            self.assertIn(row + "\n", output)

    def test_installer_options_before_help_remain_informational(self):
        expected = self.run_help("gentle-cc-install.sh")
        output = self.run_help("gentle-cc-install.sh", "--from-source", "unused",
                               "--ref", "unused-ref", "--version", "unused-version",
                               "--no-wrapper", "--sha-only")
        self.assertEqual(output, expected)


if __name__ == "__main__":
    unittest.main()
