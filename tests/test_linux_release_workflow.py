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

    def test_relevant_e2e_sources_trigger_the_linux_workflow(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        for path in (
            ".github/workflows/linux-companion-e2e.yml",
            "tests/companion-e2e.ps1",
            "tests/engram-mcp-smoke.py",
            "tests/test_linux_release_workflow.py",
            "tests/test_engram_mcp_smoke.py",
            "gentle-cc-install.sh",
        ):
            self.assertIn(path, text)


if __name__ == "__main__":
    unittest.main()
