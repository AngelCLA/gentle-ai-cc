# Release 4.3.1-cc.3

Objective: publish the maintenance release `4.3.1-cc.3` from `main`, carrying the Windows
public-install fixes, with the same companion binaries and a rebuilt native wrapper.
Branch: `chore/release-4.3.1-cc.3` from `e739b92`; delivery: single PR; test runner:
`go test ./...`, `pwsh tests/installers.ps1`, `bash tests/test_installers.sh`.

## Specs

S1. User: "Continua con la nueva release que se quedo" — publish `4.3.1-cc.3` from the
    merged `main` revision; never replace or delete the existing `4.3.1-cc.1` and
    `4.3.1-cc.2` releases.
S2. User: "gentle-shell usa engram context7 y los skills de gentle-ai" — the Command Code
    environment provisioned by the release must provide the `engram` and `context7` MCP
    entries and the gentle-ai skills; the published-companion E2E assertions for
    `AGENTS.md`, `mcpServers.engram`, `mcpServers.context7`, installed skills and shared
    state are the acceptance check.
S3. Companion provenance: the companion ref did not change since `4.3.1-cc.2`, so the
    already-verified companion binaries are reused under the new version names and
    `checksums.txt` is recomputed; the release notes state that provenance.

## Tasks

T1 | S1 | parent | done | `install.sh`, `install.ps1`, `gentle-cc-install.sh`, `gentle-cc-release.sh`, both fixture suites, `tests/companion-e2e.ps1`, `docs/linux-ci-runtime-smoke.md` and README now default to `4.3.1-cc.3`; only historical cc.2 provenance lines remain.
T2 | S1-S3 | parent | done | All six published `4.3.1-cc.2` companion assets downloaded and verified against the published manifest (e.g. linux/amd64 `9256b29e...`); six wrappers rebuilt with Go 1.27.0 reproducibly; `dist/checksums.txt` has 12 entries.
T3 | S1-S2 | parent | done | `go test ./...` and `go vet ./...` clean; `pwsh tests/installers.ps1` passes; Bash suite reports 77 passing cases plus the expected mutant RED; an isolated `install.ps1` run from `dist/` provisioned engram and context7 MCP entries, 8 skills, and left shared state without `command-code`.
T4 | S1 | parent | done | Commits `182eea2` (defaults) and `27b7ff0` (tracking) pushed; `origin/chore/release-4.3.1-cc.3` exists.
T5 | S1-S3 | parent | done | User authenticated `gh` as `AngelCLA`; release published at https://github.com/AngelCLA/gentle-ai-cc/releases/tag/4.3.1-cc.3 targeting `723e0eb` (not draft/prerelease) with 12 binaries plus `checksums.txt`; the published manifest matches local `dist/checksums.txt` byte for byte; notes state the reused-companion provenance; cc.1/cc.2 releases untouched.
T6 | S2-S3 | parent | pending | Hosted `companion-e2e` proof against the published `4.3.1-cc.3` assets.

## Log

L1. User original request: "Continua con la nueva release que se quedo gentle-shell usa engram cintext7 y los skills de gentle-ai"
L2. Prior session had proposed `4.3.1-cc.3` and stopped because `gh` was missing and unauthenticated; user replied to continue.
L3. `gh` 2.103.3 installed via winget; `gh auth status` reports no logged-in host, so publishing still needs interactive authentication.
L4. Version bump applied to nine tracked files; the test suite's help fixture mirrors `gentle-cc-install.sh` lines 2-33, so both were updated together.
L5. Companion provenance verified rather than assumed: each downloaded `4.3.1-cc.2` companion matched the published `checksums.txt` entry before being staged as `4.3.1-cc.3`. Wrapper binaries are new builds; companion hashes therefore equal cc.2 by design.
L6. Local provisioning proof used `install.ps1` against `dist/` with isolated HOME/AppData/XDG and observed `mcpServers.engram`, `mcpServers.context7`, `.commandcode/skills/*/SKILL.md` (8 skills) and a shared state without `command-code`. This is Windows amd64 evidence only; Linux runtime proof comes from the hosted E2E.
L7. Hosted E2E cannot run before publication because `tests/companion-e2e.ps1` downloads the published tag and asserts a disposable GitHub-hosted runner.
