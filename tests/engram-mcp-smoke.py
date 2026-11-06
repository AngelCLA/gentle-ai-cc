#!/usr/bin/env python3
"""Secret-free Linux Engram MCP smoke, using only the Python standard library.

Usage: python3 tests/engram-mcp-smoke.py /absolute/path/to/engram [--timeout 10]
The binary must already be installed. No download, shell, model, or credentials
are used. Each protocol request has its own timeout (seconds). All child state
is disposable; ENGRAM_DATA_DIR is the official data-directory override.
"""
import argparse
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time
import uuid


class SmokeError(Exception):
    pass


class Client:
    def __init__(self, process, timeout):
        self.process = process
        self.timeout = timeout
        self.sequence = 0
        self.buffer = b""
        self.selector = selectors.DefaultSelector()
        self.selector.register(process.stdout, selectors.EVENT_READ)

    def send(self, message):
        try:
            self.process.stdin.write((json.dumps(dict(jsonrpc="2.0", **message)) + "\n").encode())
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise SmokeError("could not write to server") from exc

    def request(self, method, params):
        self.sequence += 1
        self.send({"id": self.sequence, "method": method, "params": params})
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SmokeError("timed out waiting for " + method)
            if b"\n" not in self.buffer:
                if not self.selector.select(remaining):
                    raise SmokeError("timed out waiting for " + method)
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise SmokeError("server closed stdout during " + method)
                self.buffer += data
                if len(self.buffer) > 1024 * 1024:
                    raise SmokeError("server response exceeded 1 MiB")
                continue
            line, self.buffer = self.buffer.split(b"\n", 1)
            try:
                message = json.loads(line)
            except (ValueError, UnicodeError) as exc:
                raise SmokeError("invalid JSON from server") from exc
            if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
                raise SmokeError("invalid JSON-RPC response")
            if "id" not in message and "method" in message:
                continue  # MCP logging/resource notifications may interleave replies.
            if message.get("id") != self.sequence:
                raise SmokeError("unexpected response id")
            if "error" in message:
                raise SmokeError(method + " returned a JSON-RPC error")
            if not isinstance(message.get("result"), dict):
                raise SmokeError(method + " returned an invalid result")
            return message["result"]

    def call(self, name, arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError"):
            raise SmokeError(name + " returned a tool error")
        return result


def teardown(process):
    # Own session/process group: terminate descendants as well as the server.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdin.close()
        process.stdout.close()


def smoke(binary, timeout):
    if not binary.is_absolute() or not binary.is_file() or not os.access(binary, os.X_OK):
        raise SmokeError("binary must be an absolute executable file")
    # Explicit /tmp avoids inherited TMPDIR pointing at a home or checkout.
    with tempfile.TemporaryDirectory(prefix="engram-mcp-smoke-", dir="/tmp") as directory:
        root = Path(directory)
        paths = {"HOME": "home", "ENGRAM_DATA_DIR": "data", "XDG_CONFIG_HOME": "config",
                 "XDG_DATA_HOME": "xdg-data", "XDG_CACHE_HOME": "cache",
                 "XDG_STATE_HOME": "state", "TMPDIR": "tmp"}
        env = {}
        for key, name in paths.items():
            path = root / name
            path.mkdir(mode=0o700)
            env[key] = str(path)
        env.update(TMP=env["TMPDIR"], TEMP=env["TMPDIR"], LANG="C", LC_ALL="C")
        work = root / "work"
        work.mkdir(mode=0o700)
        # Engram requires explicit projects to be backed by local project context.
        # This config is disposable and cannot redirect the database outside root.
        project = "engram-smoke-" + uuid.uuid4().hex
        project_config = work / ".engram"
        project_config.mkdir(mode=0o700)
        (project_config / "config.json").write_text(
            json.dumps({"project_name": project}), encoding="utf-8")
        token = "engram_smoke_" + uuid.uuid4().hex
        process = subprocess.Popen([str(binary), "mcp", "--tools=agent"], cwd=work,
                                   env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, start_new_session=True)
        client = None
        try:
            client = Client(process, timeout)
            result = client.request("initialize", {
                "protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "engram-mcp-smoke", "version": "1"}})
            if result.get("protocolVersion") != "2024-11-05":
                raise SmokeError("server negotiated an unsupported protocol version")
            client.send({"method": "notifications/initialized"})
            tools = client.request("tools/list", {}).get("tools", [])
            if not isinstance(tools, list):
                raise SmokeError("tools/list returned an invalid tools list")
            names = {tool.get("name") for tool in tools if isinstance(tool, dict)
                     and isinstance(tool.get("name"), str)}
            missing = {"mem_save", "mem_search"} - names
            if missing:
                raise SmokeError("required tools missing: " + ", ".join(sorted(missing)))
            client.call("mem_save", {"title": "Synthetic MCP smoke observation",
                                    "type": "discovery", "scope": "project", "project": project,
                                    "capture_prompt": False,
                                    "content": "Synthetic disposable smoke token: " + token})
            result = client.call("mem_search", {"query": token, "project": project})
            content = result.get("content", [])
            if not isinstance(content, list) or not any(
                isinstance(item, dict) and item.get("type") == "text"
                and isinstance(item.get("text"), str) and token in item["text"]
                for item in content
            ):
                raise SmokeError("mem_search did not return the synthetic token")
        finally:
            if client is not None:
                client.selector.close()
            teardown(process)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary", type=Path, help="absolute path to an already-installed Engram binary")
    parser.add_argument("--timeout", type=float, default=10, help="positive per-request timeout in seconds (default: 10)")
    args = parser.parse_args()
    try:
        if not math.isfinite(args.timeout) or args.timeout <= 0:
            raise SmokeError("timeout must be finite and positive")
        smoke(args.binary, args.timeout)
    except (SmokeError, OSError) as exc:
        print("Engram MCP smoke failed: " + str(exc), file=sys.stderr)
        return 1
    print("Engram MCP smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
