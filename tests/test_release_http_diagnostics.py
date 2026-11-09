#!/usr/bin/env python3
"""Offline tests: subprocess is mocked; no network requests are made."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import call, patch

import release_http_diagnostics as diagnostic

URLS = (
    "https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.3/gentle-ai-cc_4.3.1-cc.3_linux_amd64",
    "https://github.com/Gentleman-Programming/engram/releases/download/v3.6.2/engram_3.6.2_linux_amd64.tar.gz",
)


class DiagnosticTests(unittest.TestCase):
    def run_probe(self, results):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"HTTPS_PROXY": "secret-proxy", "GH_TOKEN": "secret-token"}, clear=True), \
                patch.object(diagnostic.subprocess, "run", side_effect=results) as run, \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = diagnostic.main()
        self.assertEqual(stderr.getvalue(), "")
        records = [json.loads(line) for line in stdout.getvalue().splitlines()]
        return code, records, run

    def test_success_exact_two_bounded_unauthenticated_gets(self):
        result = subprocess.CompletedProcess([], 0, "HTTP/2 200\r\n\r\n\n200\n", "")
        code, records, run = self.run_probe([result, result])
        self.assertEqual(code, 0)
        self.assertEqual(records, [
            {"proxy_env_keys": ["HTTPS_PROXY"]},
            {"probe": "companion", "curl_exit": 0, "status": 200,
             "headers": [{"status": 200}]},
            {"probe": "engram", "curl_exit": 0, "status": 200,
             "headers": [{"status": 200}]},
        ])
        self.assertEqual(run.call_args_list, [call([
            "/usr/bin/curl", "-q", "--silent", "--location", "--max-redirs", "10",
            "--proto", "=https", "--proto-redir", "=https", "--max-time", "60",
            "--connect-timeout", "15", "--output", "/dev/null", "--dump-header", "-",
            "--write-out", "\n%{http_code}\n", url,
        ], capture_output=True, text=True, env={}, timeout=65) for url in URLS])

    def test_redirects_and_headers_are_strictly_sanitized(self):
        headers = (
            "HTTP/1.1 302 secret-reason\r\n"
            "Location: https://secret-user:secret-password@release-assets.githubusercontent.com/private/secret-path?sig=secret-signature\r\n"
            "Set-Cookie: secret-cookie\r\nAuthorization: secret-auth\r\n"
            "X-Secret: secret-header\r\nServer: secret-server\r\n"
            "Content-Type: secret-type\r\nContent-Length: secret-length\r\n"
            "\r\nHTTP/2 200 secret-final\r\n"
            "Content-Type: application/octet-stream\r\nContent-Length: 123\r\n\r\n\n200\n"
        )
        result = subprocess.CompletedProcess([], 0, headers, "secret-stderr signed-url?secret")
        code, records, _ = self.run_probe([result, result])
        self.assertEqual(code, 0)
        self.assertEqual(records[1]["headers"], [
            {"status": 302}, {"location_host": "release-assets.githubusercontent.com"},
            {"status": 200}, {"content-type": "application/octet-stream"},
            {"content-length": 123},
        ])
        self.assertNotIn("secret", json.dumps(records))

    def test_failures_still_probe_both_and_return_failure(self):
        ok = subprocess.CompletedProcess([], 0, "\n200\n", "")
        for failed in (subprocess.CompletedProcess([], 28, "\n000\n", "secret"),
                       subprocess.CompletedProcess([], 0, "\n504\n", "secret"),
                       subprocess.CompletedProcess([], 0, "untrusted-secret", "secret"),
                       OSError("secret"), subprocess.TimeoutExpired("secret", 65)):
            for results in ([failed, ok], [ok, failed]):
                with self.subTest(results=results):
                    code, records, run = self.run_probe(results)
                    self.assertEqual(code, 1)
                    self.assertEqual(run.call_count, 2)
                    self.assertEqual(len(records), 3)
                    failed_index = 1 if results[0] is failed else 2
                    expected_exit = failed.returncode if isinstance(failed, subprocess.CompletedProcess) else None
                    expected_status = 504 if expected_exit == 0 and failed.stdout == "\n504\n" else None
                    for index, name in ((1, "companion"), (2, "engram")):
                        self.assertEqual(records[index], {
                            "probe": name,
                            "curl_exit": expected_exit if index == failed_index else 0,
                            "status": expected_status if index == failed_index else 200,
                            "headers": [],
                        })
                    self.assertNotIn("secret", json.dumps(records))

    def test_workflow_is_manual_read_only_and_bounded(self):
        workflow = (Path(__file__).resolve().parents[1] /
                    ".github/workflows/release-http-diagnostics.yml").read_text()
        self.assertEqual(workflow.split("on:\n", 1)[1].split("\npermissions:", 1)[0].strip(),
                         "workflow_dispatch:")
        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("runs-on: ubuntu-24.04", workflow)
        self.assertIn("timeout-minutes: 5", workflow)
        self.assertIn("actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("python3 tests/release_http_diagnostics.py", workflow)
        for forbidden in ("secrets.", "token:", "upload-artifact", "install", "companion-e2e"):
            self.assertNotIn(forbidden, workflow)


if __name__ == "__main__":
    unittest.main()
