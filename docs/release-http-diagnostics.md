# Diagnose public release HTTP transport

Use **Release HTTP diagnostics** to collect sanitized HTTP evidence from a
GitHub-hosted Ubuntu 24.04 runner. This is a diagnostic, **not release proof**:
it does not verify checksums, execute binaries, exercise installers or MCP,
or replace or rerun the published companion E2E acceptance checks.

## Run manually

1. Open **Actions → Release HTTP diagnostics → Run workflow**.
2. Select the revision containing this workflow and run it once.
3. Read the **Probe fixed public release URLs without executing downloads** log.
   Both probes run even if the first fails. The job succeeds only when both
   curl processes succeed and both final HTTP statuses are exactly 200.

The two fixed GET targets are the `4.3.1-cc.3` Linux amd64 companion binary
and the `v3.6.2` Linux amd64 Engram archive, matching the published E2E fixture.
There are no URL inputs, retries, package installations or uploaded artifacts.
Bodies go directly to `/dev/null`; nothing downloaded is executed or retained.
Each probe has a 15-second connection limit, a 60-second total curl limit and
at most ten redirects. Both initial requests and redirects require HTTPS.

## Interpret sanitized output

Each probe emits a JSON line with its label, curl exit code, final HTTP status,
and sanitized redirect/response headers. A null value means unavailable.
Only numeric HTTP statuses and content lengths, three fixed binary content
types, and Location **hostnames** are recorded. Redirect paths, queries,
userinfo, cookies, authorization, reason phrases, other header values, raw
curl errors and response bodies are never logged.

The first JSON line lists only recognized proxy environment **key names**.
Curl runs with an empty environment and ignores curlrc (`-q` first), so ambient
proxy values, tokens and credential configuration are neither used nor printed.
This intentionally does not diagnose an authenticated or configured proxy route.
A successful run establishes only public HTTP reachability at that moment;
a failure is transport evidence, not a verdict about release correctness.

## Offline verification

Run `python3 -B tests/test_release_http_diagnostics.py`. The stdlib unittest suite
mocks subprocesses: it makes no network calls and checks exact curl arguments,
redaction, failure handling and workflow safety.
