#!/usr/bin/env python3
"""Bounded public HTTP diagnostics; never execute or retain response bodies."""
import json
import os
import re
import subprocess
from urllib.parse import urlsplit

PROBES = (
    ("companion", "https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.3/gentle-ai-cc_4.3.1-cc.3_linux_amd64"),
    ("engram", "https://github.com/Gentleman-Programming/engram/releases/download/v3.6.2/engram_3.6.2_linux_amd64.tar.gz"),
)
PROXY_KEYS = ("http_proxy", "https_proxy", "all_proxy", "no_proxy",
              "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")


def safe_headers(text):
    """Emit only typed values, never arbitrary header text or reason phrases."""
    headers = []
    for line in text.splitlines():
        status = re.fullmatch(r"HTTP/(?:1\.[01]|2|3) ([1-5][0-9]{2})(?: .*)?", line)
        if status:
            headers.append({"status": int(status[1])})
            continue
        key, separator, value = line.partition(":")
        if not separator:
            continue
        key, value = key.lower(), value.strip()
        if key == "location":
            try:
                host = urlsplit(value).hostname
            except ValueError:
                continue
            if host and re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?", host):
                headers.append({"location_host": host})
        elif key == "content-length" and re.fullmatch(r"[0-9]{1,18}", value):
            headers.append({key: int(value)})
        elif key == "content-type" and value in (
                "application/octet-stream", "application/gzip", "application/x-gzip"):
            headers.append({key: value})
    return headers


def probe(name, url):
    command = [
        "/usr/bin/curl", "-q", "--silent", "--location", "--max-redirs", "10",
        "--proto", "=https", "--proto-redir", "=https", "--max-time", "60",
        "--connect-timeout", "15", "--output", "/dev/null", "--dump-header", "-",
        "--write-out", "\n%{http_code}\n", url,
    ]
    record = {"probe": name, "curl_exit": None, "status": None, "headers": []}
    try:
        # An empty environment excludes tokens, proxy credentials and HOME-based
        # configuration. -q as the first option also disables ambient curlrc.
        result = subprocess.run(command, capture_output=True, text=True, env={}, timeout=65)
        record["curl_exit"] = result.returncode
        lines = result.stdout.splitlines()
        if lines and re.fullmatch(r"[1-5][0-9]{2}", lines[-1]):
            record["status"] = int(lines[-1])
        record["headers"] = safe_headers("\n".join(lines[:-1]))
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        pass  # Exception details and curl stderr may contain credentials/URLs.
    print(json.dumps(record, sort_keys=True))
    return record["curl_exit"] == 0 and record["status"] == 200


def main():
    print(json.dumps({"proxy_env_keys": sorted(key for key in PROXY_KEYS if key in os.environ)}))
    outcomes = [probe(name, url) for name, url in PROBES]
    return 0 if all(outcomes) else 1


if __name__ == "__main__":
    raise SystemExit(main())
