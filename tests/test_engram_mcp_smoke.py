#!/usr/bin/env python3
"""Offline public-CLI tests; fake MCP servers live only in system temp dirs."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLIENT = Path(__file__).with_name("engram-mcp-smoke.py")

SERVER = r'''
import json, os, pathlib, signal, sys, time
MODE = __MODE__
PID_FILE = __PID_FILE__
pathlib.Path(PID_FILE).write_text(json.dumps({"pid": os.getpid(), "root": str(pathlib.Path(os.environ["HOME"]).parent)}))
expected = {"HOME", "ENGRAM_DATA_DIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
            "XDG_CACHE_HOME", "XDG_STATE_HOME", "TMPDIR", "TMP", "TEMP", "LANG", "LC_ALL"}
assert set(os.environ) == expected, set(os.environ)
assert sys.argv[1:] == ["mcp", "--tools=agent"]
root = pathlib.Path(os.environ["HOME"]).parent
assert pathlib.Path.cwd() == root / "work"
for name in expected - {"LANG", "LC_ALL"}:
    p = pathlib.Path(os.environ[name])
    assert p.is_dir() and p.is_relative_to(root)
assert len({os.environ[k] for k in ["HOME", "ENGRAM_DATA_DIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "TMPDIR"]}) == 7
saved = None
initialized = False
for line in sys.stdin:
    request = json.loads(line)
    method = request["method"]
    if method == "notifications/initialized":
        assert "id" not in request
        initialized = True
        continue
    if MODE == "timeout":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True: time.sleep(1)
    if MODE == "exit": sys.exit(7)
    if MODE == "malformed":
        print("not json", flush=True)
        continue
    if method == "initialize":
        assert request["params"]["protocolVersion"] == "2024-11-05"
        result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
                  "serverInfo": {"name": "fake", "version": "1"}}
    elif method == "tools/list":
        assert initialized
        names = ["mem_save"] if MODE == "missing_tool" else ["mem_save", "mem_search"]
        result = {"tools": [{"name": name, "inputSchema": {"type": "object"}} for name in names]}
    else:
        assert method == "tools/call" and initialized
        args = request["params"]["arguments"]
        if request["params"]["name"] == "mem_save":
            assert args["project"].startswith("engram-smoke-")
            assert args["scope"] == "project"
            assert args["capture_prompt"] is False
            project_config = pathlib.Path.cwd() / ".engram/config.json"
            assert json.loads(project_config.read_text()) == {"project_name": args["project"]}
            saved = args
            result = {"content": [{"type": "text", "text": "saved"}]}
            if MODE == "tool_error": result["isError"] = True
        else:
            assert args["project"] == saved["project"]
            assert args["query"] in saved["content"]
            text = "no results" if MODE == "missing_token" else saved["content"]
            result = {"content": [{"type": "text", "text": text}]}
    # Notifications interleaved with replies must not disrupt request matching.
    print(json.dumps({"jsonrpc": "2.0", "method": "notifications/message", "params": {}}), flush=True)
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
'''


class SmokeTests(unittest.TestCase):
    def run_fake(self, mode):
        with tempfile.TemporaryDirectory(prefix="engram-smoke-test-") as directory:
            root = Path(directory)
            pid_file = root / "pid"
            server = root / "fake engram"
            server.write_text("#!" + sys.executable + "\n" + SERVER.replace("__MODE__", repr(mode)).replace("__PID_FILE__", repr(str(pid_file))))
            server.chmod(0o700)
            env = dict(os.environ, GH_TOKEN="must-not-leak", AWS_SECRET_ACCESS_KEY="must-not-leak", OPENAI_API_KEY="must-not-leak")
            result = subprocess.run([sys.executable, str(CLIENT), str(server), "--timeout", "0.4"],
                                    env=env, text=True, capture_output=True, timeout=8)
            self.assertTrue(pid_file.exists(), result.stderr)
            state = json.loads(pid_file.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(state["pid"], 0)
            self.assertFalse(Path(state["root"]).exists(), "isolated state was not removed")
            return result

    def test_success_isolated_environment_and_round_trip(self):
        result = self.run_fake("success")
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "Engram MCP smoke passed\n", ""))

    def test_failures_and_child_cleanup(self):
        cases = {
            "missing_tool": "required tools missing: mem_search",
            "tool_error": "mem_save returned a tool error",
            "missing_token": "mem_search did not return the synthetic token",
            "timeout": "timed out waiting for initialize",
            "exit": "server closed stdout during initialize",
            "malformed": "invalid JSON from server",
        }
        for mode, message in cases.items():
            with self.subTest(mode=mode):
                result = self.run_fake(mode)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "Engram MCP smoke failed: " + message + "\n")

    def test_relative_binary_is_rejected(self):
        result = subprocess.run([sys.executable, str(CLIENT), "relative-engram"], text=True,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "Engram MCP smoke failed: binary must be an absolute executable file\n")


if __name__ == "__main__":
    unittest.main()
