# Contributing to gentle-cc

Contributions are welcome. This repository contains the native `gentle-cc`
wrapper, installers, release packaging, and documentation. The Command Code
adapter and companion binary source live in a separate gentle-ai checkout;
changes to that adapter belong there, not in this distribution module.

## Quick start

1. Fork this repository and create a focused branch from `main`.
2. Make your change, keeping tests and documentation alongside the behavior.
3. Run the relevant checks below and open a pull request against `main`.

For a substantial change, open an issue first to discuss the problem and proposed
scope. For bug reports, include your OS and architecture, installed version,
reproduction steps, expected behavior, and actual output. Remove credentials and
personal configuration before sharing logs.

## Development setup

Clone your fork and use a Go toolchain compatible with `go.mod` (currently Go
1.25.0 or newer) for wrapper development. Bash is needed for Unix installer
fixtures; PowerShell is needed for Windows installer fixtures. Release packaging
also needs the separate companion checkout and its own Go requirements.

| Area | Location |
| --- | --- |
| Native wrapper entry point | `cmd/gentle-cc/` |
| Wrapper implementation and tests | `internal/wrapper/` |
| Installers and release packaging | Root-level shell and PowerShell scripts |
| Installer fixtures and integration probes | `tests/` |
| Hosted integration workflows | `.github/workflows/` |

## Run checks for your change

### Native wrapper

Format changed Go files with `gofmt`, then run from the repository root:

```bash
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go test ./... -v -count=1 -timeout=120s
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet ./...
```

These tests use isolated homes and a fake companion, not your real configuration.

### Installers

For Bash installer changes:

```bash
bash -n install.sh gentle-cc-install.sh gentle-cc-release.sh tests/test_installers.sh
bash tests/test_installers.sh
```

For PowerShell installer changes, run on Windows:

```powershell
pwsh -NoProfile -File tests/installers.ps1
```

Installer fixtures use temporary destinations and fake tools. Do not use a real
install or sync against your personal configuration as a substitute for tests.
See the [README regression and integration checks](README.md#native-wrapper-regression-checks)
for coverage, limitations, and published-release checks. The integration probes
download and execute real release binaries; use a disposable environment as
described in the [Linux smoke guide](docs/linux-ci-runtime-smoke.md).

### Documentation

Check that commands match the implementation, relative links resolve, and
platform claims distinguish tested behavior from unverified targets. Run
`git diff --check` before submitting any change.

## Pull request checklist

- [ ] Explain the problem, the change, and any related issue.
- [ ] Keep the change focused; avoid unrelated formatting or refactors.
- [ ] Add regression tests for behavior changes and preserve existing behavior.
- [ ] Update the README or relevant guides when commands or behavior change.
- [ ] List the checks you ran and explicitly note skipped or unavailable checks.
- [ ] Do not include generated release assets, credentials, or personal state.

Release publication is a maintainer action, separate from contributing a patch.
Contributions to this repository are provided under its [MIT License](LICENSE).
External companion code and bundled third-party components retain their own
licenses and notices.
