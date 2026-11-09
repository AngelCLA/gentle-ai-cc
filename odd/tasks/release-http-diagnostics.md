# Release HTTP diagnostics

Collect sanitized HTTP evidence on a GitHub-hosted runner without changing integration acceptance.
This diagnostic does not execute downloaded binaries or certify a release.

## Specs

- S1: "hazlo que se ocupa" — acceptance of the proposed separate manual workflow capturing HTTP headers and redirects without executing downloaded binaries or relaunching the failed integration check.

## Tasks

- [x] T1 (S1): Implement manual-only, read-only HTTP transport diagnostics with sanitization and offline tests. Route: worker. Commit: this diagnostic work unit.
- [x] T2 (S1): Independently verify workflow safety and diagnostics tests. Route: verifier. Commit: this diagnostic work unit.
- [ ] T3 (S1): Publish PR, integrate if checks pass, dispatch diagnostic once and report evidence. Route: parent. Commit: pending.

## Log

- L1: "hazlo que se ocupa"
- L2: Local HTTP GET requests to the exact companion .3 and pinned Engram 3.6.2 URLs returned 302 then 200. Failed hosted run 42579551657 had HTTP 504 on two attempts. Do not add retries, change integration conditions, authenticate the public route, or infer success from local downloads.
- L3: External PR #12 merged .5 preparation into main as 861778d; PR #13 remains open and has external head 0e71f27. Preserve those changes; diagnostic work is isolated on ci/release-http-diagnostics.
- L4: Writer observed import-failure RED then four offline tests GREEN. Independent verifier and parent ran the four tests successfully and inspected workflow permissions, fixed HTTPS URLs, timeouts, no retries, sanitization and unchanged E2E. Curl intentionally runs with empty environment and disabled curlrc; this does not reproduce a configured proxy route. Diagnostic results are not release acceptance evidence.
