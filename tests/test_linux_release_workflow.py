import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/linux-companion-e2e.yml"


class LinuxCompanionWorkflowTests(unittest.TestCase):
    def test_publishes_release_e2e_on_main_push_pr_and_manual_dispatch(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        header = text.split("\njobs:\n", 1)[0]
        for event in ("push", "pull_request"):
            self.assertRegex(
                header,
                rf"(?ms)^  {event}:\n(?:(?!^  [a-z_]+:).)*?^    branches:\n      - main\n",
            )
        self.assertRegex(header, r"(?m)^  workflow_dispatch:\s*$")

    def test_is_linux_only_least_privilege_and_has_no_secret_escalation(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("runs-on: ubuntu-24.04", text)
        self.assertRegex(text, r"(?m)^permissions:\n  contents: read$")
        self.assertIn("persist-credentials: false", text)
        self.assertNotIn("pull_request_target", text)
        self.assertNotRegex(text, r"secrets\.[A-Za-z_]")

    def test_main_push_and_pull_request_are_not_path_filtered(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        triggers = text.split("\njobs:\n", 1)[0]
        self.assertNotRegex(triggers, r"(?m)^\s+paths(?:-ignore)?:")

    def test_linux_e2e_pins_engram_and_executes_real_mcp_smoke(self):
        e2e = (ROOT / "tests/companion-e2e.ps1").read_text(encoding="utf-8")
        self.assertIn("3.6.2", e2e)
        self.assertIn("3527b7e7e8692fd4aaaf576d331cded19155523cf8b02c2de38744cccb229e89", e2e)
        self.assertIn("ENGRAM_DATA_DIR", e2e)
        self.assertIn("engram-mcp-smoke.py", e2e)
        self.assertIn("Engram MCP runtime smoke", e2e)
        self.assertIn("Engram MCP command does not resolve to the checksum-verified test binary", e2e)

    def test_e2e_checks_expected_skill_and_local_reference_artifacts(self):
        e2e = (ROOT / "tests/companion-e2e.ps1").read_text(encoding="utf-8")
        self.assertIn("skill-creator", e2e)
        self.assertIn("skill-style-guide.md", e2e)

    def test_linux_workflow_runs_offline_harness_tests_before_hosted_e2e(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("python3 tests/test_linux_release_workflow.py", text)
        self.assertIn("python3 tests/test_engram_mcp_smoke.py", text)


if __name__ == "__main__":
    unittest.main()
