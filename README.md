# gentle-cc — Command Code companion distribution for gentle-ai

Use the **official `gentle-ai` release** for every supported agent *and* use
**Command Code** (`command-code`), without waiting for upstream to accept a
Command Code adapter. Release installation needs no gentle-ai source checkout.
A user-run Linux amd64 smoke test has now completed; broader Linux distribution
and architecture coverage remains unverified.

> Command Code support is **not** upstream. Issues #1913 (approved, then
> `NOT_PLANNED`), #4105 and #5790 were closed under the policy *"we're not
> accepting new agents for now."* This is a community workaround.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, checks, and pull
request guidelines.

## License

This repository is licensed under the [MIT License](LICENSE).
The external gentle-ai companion and any bundled third-party components retain
their own licenses and notices; this license does not relicense them.

## Native wrapper (`4.3.1-cc.4` release preparation)

This distribution ships a standalone Go wrapper: running downloaded native
binaries requires **neither Python nor Bash nor Go**. Installers still need Bash
or PowerShell; source builds need Go. The companion remains a separate executable.

`4.3.1-cc.4` is the prepared native release and the default version in both
installers. Until it is published, use `GENTLE_CC_VERSION=4.3.1-cc.3` for the
already published release (without Gentle AI branding). Published-release E2E
scripts, workflows and their detailed guide intentionally remain pinned to `.3`
until `.4` assets are public, avoiding a circular dependency in pre-release PR CI.
The older `4.3.1-cc.1` release used a universal Bash wrapper, **not**
the native asset format described here; `--no-wrapper` remains the explicit
companion-only path for it and does not upgrade an existing legacy wrapper.

The `4.3.1-cc.3` companion binaries are byte-identical to `4.3.1-cc.2` and
`4.3.1-cc.1` because the companion ref did not change, so the companion still
reports `4.3.1-cc.1` from `version`; only the wrapper is a new native build.

### Release notes: `4.3.1-cc.4` (not yet published)

- The native wrapper adds optional Gentle AI decoration automatically after a
  successful mutating `install` and shared-state cleanup. The original Command
  Code banner remains; `sync` and `sync-all` do not restore a removed mod.
- After a failed mutating companion leaves `installed_agents: null`, the wrapper
  restores the validated pre-companion non-Command-Code agent list, preserves
  other post-child state, warns, and retains the companion's failure status.
  Pre-existing null and other invalid state remain rejected.
- Installer and release-packaging defaults advance to `4.3.1-cc.4`. The companion
  source pin is unchanged. Companion assets reused from a previous verified
  release retain their embedded version; record artifact provenance when publishing.
- Branding is new in `.4`, not the published `.3` wrapper. See
  [Gentle AI decoration](#gentle-ai-decoration-431-cc4) for opt-out and safety details.

## Release install

This repository publishes **public** release assets, so the default install needs
no authentication and no `gh`:

```bash
git clone https://github.com/AngelCLA/gentle-ai-cc.git
cd gentle-ai-cc
./install.sh
```

Use `GENTLE_CC_VERSION=<tag> ./install.sh` to install a different release. The
installer first honors an explicit `GENTLE_CC_SOURCE` override (source build).
Otherwise it selects local artifacts when `dist/checksums.txt` exists, then an
authenticated `gh` when it is installed and authenticated, and finally the public
HTTPS release URL. There is **no automatic source fallback**; a selected
incomplete or invalid local release fails rather than downloading.
Release mode installs the companion binary for your OS/arch **and** the
`gentle-cc` wrapper, verifying both against `checksums.txt`, to `~/.local/bin`.
Checksums establish consistency with the manifest, not publisher authenticity.

Ensure that directory is on `PATH` (installers do not configure your shell):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then, after reviewing the shared-state and concurrency warnings below:

```bash
gentle-cc install --preset full-gentleman   # first time
gentle-cc sync                              # subsequent
```

`GENTLE_CC_VERSION` pins another release; the default is `4.3.1-cc.4`.
`GENTLE_CC_DEST` changes the install directory, not the wrapper's binary lookup:
for a custom directory, add it to `PATH` and set `GENTLE_CC_BIN` to the installed
companion's full path.

### Prerequisites

- Bash installers: Bash and standard POSIX command-line tools. The native wrapper
  requires no interpreter; mutating calls need a filesystem with working OS locks.
- Release installation: `curl` (including the local `file://` path), `sha256sum`
  or `shasum -a 256`, and trusted release artifacts/manifest.
- Release download: Git for the clone. `gh` is optional: when it is installed and
  authenticated it is used first, otherwise the public HTTPS release URL is used.
- Source builds and release packaging: Git and a compatible Go toolchain with
  required module dependencies available. The pinned source currently requires
  Go 1.25.10 or newer; other refs may differ. Release users do not need Go.
- Windows: PowerShell and `Get-FileHash`; `gh` is optional for public releases.
  Installs both native `.exe` files together in the destination shown below.

## What this is

The official binary manages opencode / pi / vscode-copilot / etc. A companion
binary built from the branch that carries the Command Code adapter manages
`command-code` only. The wrapper runs the companion for `command-code` and keeps
the shared `state.json` compatible with the official binary.

| File | Role |
| --- | --- |
| `gentle-ai-cc` | Companion binary (has the Command Code adapter). |
| `cmd/gentle-cc/` | Native wrapper entry point: runs the companion only for `command-code`, cleans shared state. |
| `gentle-cc-release.sh` | Packages checked-out source for six targets + wrapper + `checksums.txt`. |
| `gentle-cc-install.sh` | Verifies release checksums before installation **or** builds from a source ref. |
| `install.sh` | POSIX convenience installer (clone-based; public release or local `dist/`). |
| `install.ps1` | Windows installer (PowerShell; isolated native installer fixtures, not real companion E2E). |

## Platform support

Packaging targets are not runtime certification or a claim that assets have
been published:

| OS / arch packaging targets | Installer / wrapper | Runtime evidence here |
| --- | --- | --- |
| Linux amd64 / arm64 | `install.sh` / native Go wrapper | Ubuntu 24.04 hosted public-release E2E passed (run [#42291955712](https://github.com/AngelCLA/gentle-ai-cc/actions/runs/42291955712)); user-run Linux amd64 smoke test also verified release installation and checksums, `install --preset full-gentleman` (21 verification checks), `sync`, and Command Code loading global MCP/skill configuration. Other distributions and arm64 runtime remain unverified. |
| macOS amd64 / arm64 | `install.sh` / native Go wrapper | Cross-compilation only; Unix runtime not certified. |
| Windows amd64 / arm64 | `install.ps1` / native Go wrapper | Windows 2022 hosted public-release E2E passed (run [#42291955712](https://github.com/AngelCLA/gentle-ai-cc/actions/runs/42291955712)); arm64 runtime remains unverified. |

On **Windows**, run `install.ps1`; it uses a prepared native release or local
`dist/`. The wrapper locates the companion as a sibling `gentle-ai-cc.exe`:

```powershell
$env:GENTLE_CC_DEST = Join-Path $env:LOCALAPPDATA "gentle-cc"
pwsh -NoProfile -File .\install.ps1
& (Join-Path $env:GENTLE_CC_DEST "gentle-cc.exe") install --preset full-gentleman
& (Join-Path $env:GENTLE_CC_DEST "gentle-cc.exe") sync
```

Set `GENTLE_CC_VERSION` only to install a different release tag.

No `PATH` configuration or runtime interpreter is needed for these absolute
paths. `GENTLE_CC_BIN` still overrides companion lookup. Native Windows symlink
privilege and attached-console termination proof remain limited; WSL/Unix runtime
has not been certified. Direct binary writes bypass cleanup and wrapper locking;
do not run them concurrently with the wrapper or each other.

`install.ps1` uses local `dist/` only when **both** requested native version/platform
assets and both checksum entries are present. Otherwise it downloads into fresh
temporary staging, never using `dist/` as a download cache: authenticated `gh`
when available, otherwise the public HTTPS release URL. A failed `gh auth status`
(including native stderr under Windows PowerShell 5.1) selects public HTTPS;
a download failure or checksum mismatch aborts installation. Owned staging is
cleaned on success and failure. A complete but corrupt local release fails
checksum verification rather than silently falling back to a download.

The hosted Windows E2E copies only `install.ps1` into a clean staging directory
and hides `gh` from `PATH`, so it exercises unauthenticated public HTTPS download
rather than a prepared local release. It then runs the installed binaries through
`version`, wrapper `install --preset full-gentleman`, and `sync` in an isolated
user profile. This Windows 2022 amd64 path passed in hosted run
[#42291955712](https://github.com/AngelCLA/gentle-ai-cc/actions/runs/42291955712).
It does not certify arm64, every Windows version, or every full-preset network
integration.
The PowerShell installer rejects an existing directory or reparse point at
either `gentle-ai-cc.exe` or `gentle-cc.exe`, and rejects a linked/non-directory
destination directory before writes. It stages both files and backups before
publication; controlled failures restore only successfully replaced files,
removing newly created files on rollback. Failed restoration retains backups
with an explicit manual-recovery warning. This is **not pair-atomic or crash-safe**.
Use an exclusively controlled destination; concurrent path swaps and linked
parent directories are not protected by this check. The hosted Windows 2022 run
[#42291955712](https://github.com/AngelCLA/gentle-ai-cc/actions/runs/42291955712)
passed both native PowerShell installer fixtures and the published companion
install/sync smoke. It does not certify arm64 or native Windows symlink privilege.

## Do I need the gentle-ai repo or the official binary?

**No.** The companion (`gentle-ai-cc`) is a **complete gentle-ai binary**: the same
program compiled from the branch that also carries the Command Code adapter. It is
not a plugin and does not load the official binary or the project source at run
time.

Previously recorded: `gentle-ai-cc install --agent command-code` succeeded in a
clean `HOME` without an official binary or checkout. That historical observation
has not been revalidated here and is not current end-to-end proof.

Who needs what:

| Role | Repo checkout | Go | Official binary |
| --- | --- | --- | --- |
| **User installing a release** (`--from-release`) | No | No | Not required |
| **User building from source** (`--from-source`) | Yes | Yes | Not required |
| **Maintainer packaging a release** | Yes | Yes | — |

If you already have the official `gentle-ai` installed, the official binary
manages the other agents, the companion manages `command-code`, and the wrapper
keeps the shared `state.json` compatible (see below). Run them sequentially:
direct binary invocations do not honor the wrapper lock. The companion is a
second full binary (~31 MB), not a small add-on.

Data the companion writes (same shape as any managed agent):

- `~/.commandcode/AGENTS.md` — managed marker sections (persona, engram
  protocol, orchestrator, agent routing, remote authorization), preserving your
  own content.
- `~/.commandcode/skills/<skill>/SKILL.md` — selected skills.
- `~/.commandcode/mcp.json` — `engram` and `context7` stdio entries.

## Installation options

### A. Prebuilt release (no Go)

For the public release, the clone + `./install.sh` quick path above is enough;
`gh` is optional. The low-level installer uses **unauthenticated `curl`**, which
works for public assets and trusted local directories. Example:

```bash
./gentle-cc-install.sh --from-release file:///absolute/path/to/release --version <version>
```

or directly against the public release:

```bash
./gentle-cc-install.sh --from-release \
  https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.4 --version 4.3.1-cc.4
```

The directory must contain `checksums.txt`, the matching platform/version binary,
and `gentle-cc_<version>_<os>_<arch>[.exe]` (unless `--no-wrapper`).
Companion assets remain `gentle-ai-cc_<version>_<os>_<arch>[.exe]`.
The installed names are `gentle-ai-cc` and `gentle-cc` (both `.exe` on Windows).
A private mirror still requires an accessible endpoint; the public release does not.

### B. Build from source at a pinned commit (needs Go)

This builds the **gentle-ai** module, so `--from-source` must point at a checkout
of gentle-ai that contains the Command Code adapter (a fork/branch with
`internal/agents/commandcode/`). It does **not** work against this distribution
repo for the companion. This distribution now has its own separate Go module
for the native wrapper.

The native wrapper is **built from this distribution's Go module**, never the
external gentle-ai module or a Bash wrapper. Keep `go.mod`,
`cmd/`, `internal/`, and the installer from the same distribution checkout.
To build only the wrapper from this distribution checkout (Go 1.25.0 or newer):

```bash
go build -trimpath -buildvcs=false -o ./dist/gentle-cc ./cmd/gentle-cc
./dist/gentle-cc --help
```

On native Windows, use PowerShell and an `.exe` output:

```powershell
go build -trimpath -buildvcs=false -o .\dist\gentle-cc.exe .\cmd\gentle-cc
.\dist\gentle-cc.exe --help
```

These commands build **only the wrapper**, not the companion. Before using other
commands, install the separate companion: on Windows place `gentle-ai-cc.exe`
beside the wrapper, or set `GENTLE_CC_BIN` to its full path on either platform.
`gentle-cc build` builds the **companion**, not the wrapper; a missing companion
also triggers that build, requiring Go and the external adapter checkout.

Source installer mode checks for the wrapper module before cloning, then builds and stages the
wrapper and companion before changing the destination. A missing module or failed
build leaves existing destinations untouched. `--no-wrapper` skips the wrapper
module check and build entirely, preserving any existing wrapper. Both Bash modes
use the publication recovery described below.

```bash
./gentle-cc-install.sh --from-source https://github.com/<you>/gentle-ai.git --ref <pinned-commit>
```

`--ref` selects the source commit/tag (default
`768e6b213c795f574ee837e3a6ce9b4274ee6280`). `--version` selects the release asset
version or injected source build version (default `4.3.1-cc.4`); it does not
select a source ref. See `./gentle-cc-install.sh --help` for options.

Both install `~/.local/bin/gentle-ai-cc` and, unless `--no-wrapper`,
`~/.local/bin/gentle-cc`. For releases, all requested artifacts are staged and
verified against `checksums.txt` **before either destination is replaced**. A
missing download or failed verification leaves existing binary/wrapper bytes
and modes unchanged. `--no-wrapper` does not download or verify the wrapper;
`--sha-only` still installs, but suppresses the final next-step guidance.
The Bash installer stages new requested files and mode-preserving backups in a
private `.gentle-cc-install.*` directory on the destination filesystem. It sets
executable permissions before publication and retains backups until both requested
replacements finish. Controlled staging, snapshot, permission, or rename failures
exit with status 1: only artifacts successfully replaced by that invocation are
restored to their previous bytes and modes (newly created artifacts are removed).
Unrelated files and an unrequested wrapper are not changed. Requested symlinks,
directories, and other non-regular files are rejected before publication, rather
than followed; a symlink destination directory is also rejected.

This is **not an atomic two-file installation or crash-safe recovery**. Use an
exclusively controlled destination: do not run concurrent installers or allow
other writers to swap its paths or parent directories. Readers can observe the
interval between renames. Signals, shell termination, SIGKILL, power loss, and
filesystem failures can interrupt publication or restoration; no signal-triggered
rollback is guaranteed. If restoration fails, stderr explicitly names the failed
artifact and retained backup directory for manual recovery; do not discard those
backups. Interrupted publication may also leave that directory. There is no
automatic recovery command. Inspect the destination and backups before separately
authorizing any manual recovery. These guarantees apply to `gentle-cc-install.sh`
in Bash. PowerShell also verifies the full pair and uses staged backups with
controlled-failure rollback; neither installer promises concurrent-path safety,
pair atomicity, signal recovery, or crash safety.
Authenticated `install.sh` downloads clean their staging on both child success
and failure, preserving the child's exit status.

## Commands

```bash
gentle-cc build             # build the companion from a branch checkout
gentle-cc install [args]    # install only Command Code (companion)
gentle-cc sync    [args]    # refresh only Command Code (companion)
gentle-cc doctor  [args]    # run doctor with the companion binary
gentle-cc sync-all [args]   # official sync for other agents + Command Code
```

### Gentle AI decoration (`4.3.1-cc.4`)

The `.4` wrapper (also buildable from this checkout) adds a small textual rose and **Gentle AI**
label above Command Code's input after a successful mutating `gentle-cc install`
and successful shared-state cleanup. This is not part of the already published
`4.3.1-cc.3` wrapper. It installs a self-contained loose mod at
`~/.commandcode/mods/gentle-ai-branding.ts` (Windows: the same path below the
wrapper's HOME/USERPROFILE). The companion itself is unchanged.

This is additive decoration, **not a replacement for the original Command Code
banner**, a full theme, or evidence that any tool has run. It uses the
[documented mods UI widget API](https://commandcode.ai/docs/mods), with
`placement: 'above-editor'` and an array of text nodes from `render`. The mod
exports the documented default factory using plain JavaScript syntax, with no
runtime package imports. A deterministic Node mock checks the installed factory
when Node is available in development; otherwise tests check its structural form.
Neither check certifies the actual Command Code loader. That API is
experimental; rendering and compatibility with your installed Command Code
version require a real-client check. The static mod has no hooks, network
requests, tool calls, or settings changes.

Automatic installation happens **only on install**. `sync` and `sync-all` never
create or refresh it. Delete `~/.commandcode/mods/gentle-ai-branding.ts` to remove
the decoration; later syncs respect that decision. Running a new mutating
`install` opts in again if the file is absent. Existing byte-identical content is
a no-op; an existing custom/modified file, directory or link is never replaced.
Help and any argument containing `dry-run` skip branding, even with other
options, after `--`, or with `=false`. This extra safeguard does not change the
existing conservative shared-state cleanup/locking classification below.

Branding runs under the existing guardian lock and skips an already cancelled
operation. It opens checked directory handles, rejects linked or non-directory
components (including HOME ancestors), and creates the file exclusively, never
truncating an existing path. A linked home must be replaced with a real path in
HOME to enable decoration. A conflict or I/O failure prints:

```text
gentle-cc: warning: Gentle AI branding not installed; existing or unsafe path preserved (see README)
```

This warning does not change the child's successful exit or undo cleanup. Newly
created configuration directories or a partial new mod can remain after an I/O
failure or interruption; inspect them before any separately authorized manual
repair. Exclusive creation prevents replacement, but is not crash-atomic
publication: a concurrent client can briefly see an incomplete newly created
file. Use a locally controlled home and restart Command Code after installation
or removal if it does not reload mods automatically.

### Wrapper-owned agent selection

`sync`, `install`, and `sync-all` reject every user token named `--agent`,
`-agent`, `--agents`, or `-agents`, bare or with `=value`, including empty values,
repeated selectors, and attempts to select `command-code` itself.
This also applies with any help alias, dry-run,
and after `--`. Rejection occurs before state preflight, locking, builds,
either binary invocation, or any state writes: exit status **1**, empty stdout,
and exactly this stderr line:

```text
gentle-cc: agent selection is managed by the wrapper; not allowed for sync, install, or sync-all
```

Omit the selector: the wrapper supplies `command-code` to the companion and, for
`sync-all`, the recorded other-agent list to the official binary. `doctor`,
`build`, and top-level help retain their existing argument behavior; this guard
is not a restriction on direct binary invocations.

The check is deliberately token-based, not an emulation of the external parser.
A standalone `--agent=pi` is rejected even after an option that might consume it
as data; use an attached value such as `--preset=--agent=pi` to express that data.
Embedded text such as `some--agent=pi` is forwarded unchanged.

Read-only source inspection of the companion checkout pinned at
`768e6b213c795f574ee837e3a6ce9b4274ee6280` confirmed that Go `flag.FlagSet`
registers `agent` and `agents` to the same append-only slice: repeated selectors
accumulate rather than replace the wrapper's selector. Both one/two hyphens and
separate/attached values are supported; no `-a` is registered. The guard covers
these forms without depending on their order or parser boundaries. This is source
evidence, not execution of that checkout. Other companion versions and the
installed official binary's parser have not been verified.

## Reproducibility and integrity

- Source installation and release packaging use `-trimpath -buildvcs=false`,
  `CGO_ENABLED=0`, and an injected `--version`. These reduce build-path/VCS
  variation, not all sources of variation. Byte-identical builds require identical
  clean source inputs, Go toolchain, dependencies, target and build environment.
- `gentle-cc-release.sh` builds the **currently checked-out source**, including
  local changes; it does not pin or enforce a clean commit. Inspect that external
  checkout and record its commit, cleanliness and toolchain before packaging.
  The distribution's wrapper Go source is also an input. Previously recorded six-target matching hashes
  have not been revalidated here; there is no universal reproducibility guarantee.
- Installer fixture tests cover checksum rejection with fake artifacts; this is
  not proof of real release provenance or runtime behavior. Trust the source of
  the manifest as well as checking hashes.
- Pin the source commit (`--ref`) or release tag in shared instructions. A tag or
  version string alone does not prove immutable, identical inputs.

## Native wrapper regression checks

Run the public executable suite and static checks from this distribution checkout:

```bash
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go test ./... -v -count=1 -timeout=120s
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet ./...
```

Tests build `./cmd/gentle-cc` and a separate Go fake companion in system temporary
storage. Wrapper invocations use isolated homes and a tool search path without
Python or Bash. They cover routing, selector/custom-home rejection, conservative
help/dry-run classification, failure exits, schema validation, no-op and
large-number preservation, atomic replacement, lock contention and guardian
lifetime after invoking-process death. They do not execute the real companion or
write user configuration. Go is a test/build dependency, not a release runtime
dependency. See `internal/wrapper/*_test.go` for the native parity suite.

Windows symlink tests may skip without privilege, and Control-Break delivery
requires an attached console; unavailable checks remain **uncertified**, not
passes. Linux/macOS runtime and real companion/global concurrency have not been
certified by Windows fixtures or six-target cross-compilation.

## Installer regression checks

Run the Bash installer fixtures without Python (no real downloads, Go builds,
companion execution, or installs into your home directory):

```bash
bash -n tests/test_installers.sh
bash tests/test_installers.sh
```

The suite invokes isolated copies of the public installers with fake transport,
Git and Go tools. It checks release verification, source wrapper provenance,
publication/rollback failures, destination rejection and authenticated child
status/cleanup. A deliberately wrong isolated installer must fail a byte assertion
(`RED`) before the real fixtures pass (`GREEN`). Scratch state is removed on exit.
On filesystems without real POSIX modes or symlinks, the suite prints explicit
`LIMITATION` messages; those checks are **not** platform certification. Fake curl
avoids Git Bash's native `file://` transport limitations without skipping release
assertions. These fixtures do not certify real companion or wrapper runtime.

Run the separate Windows installer fixtures directly (no Python required):

```powershell
pwsh -NoProfile -File tests/installers.ps1
```

The PowerShell fixtures use fake `gh` downloads and temporary destinations to
check complete-pair local/version selection, both checksums, native-command
failures, unchanged local artifacts, staging cleanup, publication rollback,
directory/reparse-point rejection for both executables, and native guidance.

Bash and PowerShell here test **installers**, not wrapper runtime dependencies.
Run those suites independently of the native Go wrapper suite. Historical ODD
logs record legacy Bash/Python evidence; they are not the current test commands.
None of these suites certifies the separate future Linux probe.

## Published-release integration checks

`.github/workflows/linux-companion-e2e.yml` runs the published-release E2E on
`ubuntu-24.04` for pushes to `main`, pull requests targeting `main`, and manual
dispatch. It uses a disposable runner home, read-only repository
permissions, and no configured secrets. Network access is unrestricted.
The test intentionally still downloads published `4.3.1-cc.3`, not the prepared
`.4` installer default, until `.4` is published; this avoids requiring unpublished
assets for PR CI. It downloads a checksum-pinned Engram `v3.6.2` binary,
then runs the companion `install`/`sync`, verifies that the generated MCP
entry resolves to that checksum-pinned binary, performs an actual Engram MCP
stdio initialize/list/save/search round-trip against synthetic data in a
separate temporary data directory, and checks the installed `skill-creator` and
its local style-guide file. It does not invoke a model: skill checks establish
artifact presence/content markers, not model adherence. This is Linux amd64
runner evidence, not a guarantee for every Linux distribution or architecture.
The existing `.github/workflows/companion-e2e.yml` keeps its separate
branch-specific/manual Ubuntu and Windows matrix; this change does not expand
Windows or macOS validation. See [the detailed Linux smoke guide](docs/linux-ci-runtime-smoke.md)
for the workflow diagram, isolation boundaries, protocol details, and limitations.

## Publishing a release (for the maintainer)

These are manual maintainer instructions, not a release performed or authorized
by this preparation. Release publication and support commitments are not
established here. See [License](#license) for this repository's licensing.

1. In the **external gentle-ai companion checkout**, keep the adapter branch
   rebased on its upstream `origin/main` so guidance tracks the official release.
   This does not mean rebasing this separate distribution module onto gentle-ai.
   Review upstream changes and verify the target runtimes before publication.
2. Build artifacts (binaries + wrapper + manifest):

   ```bash
   ./gentle-cc-release.sh --repo ~/dev/gentle-ai --version <version> --out dist
   ```

   The script builds both modules with the same reproducibility flags for
   Linux/macOS/Windows amd64/arm64 and includes all 12 native assets in
   `checksums.txt`. The obsolete single-file `--wrapper PATH` override is rejected
   (exit 2); it cannot represent six architecture-specific executables. No Bash
   wrapper is copied into native release output. Always choose a new version;
   do not replace the legacy `4.3.1-cc.1` release with incompatible assets.
   When the companion ref did not change, the previously verified companion
   binaries may be reused under the new version names instead of being rebuilt;
   recompute `checksums.txt` and state the provenance in the release notes.

3. Publish under that tag:

   ```bash
   gh release create <version> dist/* --title <version> --notes "Native Command Code distribution"
   ```

4. Share the clone + `./install.sh` instructions. The release assets are public;
   an explicit `GENTLE_CC_VERSION` installs a different tag.
5. On each new upstream release: update the external adapter checkout, bump
   `--version`, verify, rebuild and publish only when separately authorized;
   update the pinned `--ref`/tag in distribution instructions.

## The shared-state detail

`~/.gentle-ai/state.json` is shared by both binaries. The official binary
**fails its real `sync`** when `installed_agents` contains an ID it does not
know:

```
Error: execute sync pipeline: create adapter for "command-code":
agent "command-code" is not supported in MVP
```

The companion's `install` records `command-code` there. After mutating
`install`/`sync` operations, the wrapper **removes only** `command-code` and the
stale `commandcode` from `installed_agents`, preserving other agents (including
duplicates) and unrelated JSON bytes, including arbitrary-precision numbers.
Missing state is not created by cleanup. If there is nothing to remove, cleanup
does not rewrite the file or change its identity/mtime. Otherwise it writes a
temporary file in the same directory, preserves permission bits, flushes and
syncs the file, then atomically replaces `state.json` (Unix rename; Windows
`ReplaceFileW`). Already-open compatible readers retain the old file; a Windows
reader denying delete sharing can prevent replacement, which fails without a
copy/delete fallback. This does not make the companion's own writes atomic or
promise durability across every filesystem/power failure.

The wrapper uses nonempty `HOME`, falling back to Go's `os.UserHomeDir()` (on
Windows, `USERPROFILE`), for its default paths and `.gentle-ai` state directory.
Custom state homes (`GENTLE_AI_HOME`) are **unsupported by the wrapper**.
Mutating `install`, `sync`, and `sync-all` reject any nonempty `GENTLE_AI_HOME`
before state preflight, locking,
builds or binaries: exit status **1**, empty stdout, and exactly:

```text
gentle-cc: GENTLE_AI_HOME is unsupported for mutating wrapper commands; unset it
```

Unset it before mutations (an empty value is accepted). Help/read-only routing
is unchanged; this does not implement custom-home isolation. Conservatively
classified calls, including ambiguous dry-runs, also reject the override.

Before invoking a mutating binary, the native guardian acquires the lock and
validates existing state (a JSON object with an optional `installed_agents` list
of strings). Missing state is allowed; malformed JSON, invalid schema and I/O
errors fail with `gentle-cc: cannot clean shared state: <detail>` rather than
being silently ignored. A companion failure retains its exit status if cleanup
succeeds; a cleanup failure returns status 1 instead. An official sync failure
returns status 1 with `gentle-cc: official sync failed`, without running the
companion or cleanup.

There is one narrow recovery for mutating `install`, `sync`, and `sync-all`:
if the companion fails and leaves a valid JSON object whose effective
`installed_agents` field is exactly `null`, the wrapper replaces only that value
with the validated list captured immediately before the companion, excluding
`command-code` and `commandcode` but retaining other agents and duplicates.
Missing pre-companion state or an absent field yields `[]`. For `sync-all`, the
snapshot is taken **after** successful official sync, so its valid agent-list
updates are retained. All unrelated post-child JSON bytes and permission bits
are preserved using the same atomic replacement as ordinary cleanup. Successful
recovery retains the companion's nonzero status and prints exactly:

```text
gentle-cc: warning: recovered installed_agents from pre-companion state after companion failure; other state preserved
```

This repairs only the shared agent-list field, not a failed installation or a
transaction rollback. Pre-existing null, null after a successful companion,
malformed JSON, mixed-type lists and other invalid schemas are still rejected;
failed recovery returns the ordinary cleanup error/status 1. Help/read-only calls
do not recover state. Direct/concurrent binary writes remain unsupported.

A persistent regular single-link file at `~/.gentle-ai/gentle-cc.lock`, locked
with native `flock` on Linux/macOS or `LockFileEx` on Windows, serializes wrapper
mutations, including the **entire** `sync-all` operation and cleanup. A held lock
or a legacy directory lock fails immediately:
`gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions`.
Exit status is 1, stdout is empty, and shared state and binaries are untouched.
Symlinks/reparse points and hardlinks are rejected; lock acquisition fails closed.
Other failures include `gentle-cc: cannot acquire shared-state OS lock; no mutation started`
and `gentle-cc: cannot acquire shared-state lock; lock must be a regular single-link file`.
Unsupported platforms report
`gentle-cc: OS locking unavailable; supported platforms are Windows, Linux and macOS`.
Use a locally controlled filesystem with working OS locks.

The lock file remains after completion: **never unlink, replace, or recreate it**,
even when idle (doing so splits contenders across different file identities).
A separate native guardian owns the lock until foreground children finish and
cleanup completes. Killing only the invoking wrapper does not release that lock;
pipe EOF is not cancellation. Interrupt/termination requests are forwarded to the
writer's process group (Unix signals; Windows Control-Break requires a console).
The invoking process may exit before the writer finishes; the guardian keeps the
lock even for a signal-ignoring writer. Normal guardian exit closes the lock
without deleting its file. Killing the guardian or the entire process tree can
interrupt cleanup; OS lock release is not a transaction or automatic state repair.
Daemonized/background writers are outside this guarantee: do not use binaries
that leave background writers. Apart from the targeted failed-companion null-field
recovery above, no state recovery or lock migration runs automatically.

**Do not run direct official or companion writes simultaneously with the
wrapper or each other.** Neither external binary honors this wrapper-only lock;
atomic cleanup cannot prevent their lost updates. `sync-all` runs official sync
first and companion sync second, but is not a transaction with rollback.

After selector rejection, companion-only `sync`/`install` recognize `--help`,
`-help`, `-h`, and `--h` anywhere, matching the pinned companion's pre-dispatch
help scan (even after `--` or a positional). Those calls skip cleanup and locking.
For `sync-all`, the official parser is unverified: only unambiguous `--help`/`-h`
combined solely with recognized dry-run/help tokens bypass locking. Other help
aliases, option values, unknown options, positionals, and `--` take the locked
preflight/cleanup path, even if the companion itself would only show help.

For a sequence consisting only of `--dry-run`/`-dry-run` tokens, the **last value
wins**, including mixed hyphens: `--dry-run -dry-run=false` requires state preflight,
locking, and cleanup; `-dry-run=false --dry-run` skips locking and cleanup.
Bare flags mean true; values must be attached with `=`. Go boolean spellings are
supported: `1`, `t`, `T`, `true`, `TRUE`, `True` mean true; `0`, `f`, `F`, `false`,
`FALSE`, `False` mean false. Any other token makes dry-run classification
conservative: for example `--preset full --dry-run`, `-- --dry-run`, and
`--dry-run false` use the locked path instead of guessing parser semantics.
The wrapper does not validate every command-specific option; the binary still
parses the unchanged arguments and may reject them. A conservative path can
create the persistent lock file and perform cleanup even for a binary dry-run.
Straightforward informational invocations leave state untouched by the wrapper;
`sync-all` still reads and validates state to obtain the other-agent list.
Dry-run can hide unsupported-agent errors because it does not build adapters;
verify compatibility with a real `sync`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `GENTLE_CC_REPO` | `~/dev/gentle-ai` | Branch checkout used to build the companion. |
| `GENTLE_CC_BIN` | Unix: `~/.local/bin/gentle-ai-cc`; Windows native: sibling `gentle-ai-cc.exe` | Companion binary path override. |
| `GENTLE_AI_BIN` | `gentle-ai` | Official binary used by `sync-all`. |
| `GENTLE_AI_HOME` | Unset | Custom state home unsupported by wrapper mutations; any nonempty value is rejected. |
| `GENTLE_CC_DEST` | Bash: `~/.local/bin`; PowerShell: `$env:LOCALAPPDATA\gentle-cc` | Installer destination; does not change wrapper lookup or `PATH`. |
| `GENTLE_CC_VERSION` | `4.3.1-cc.4` | Release tag / build version passed by `install.sh`; release tag in PowerShell. |
| `GENTLE_CC_SOURCE` | Unset | `install.sh` source Git URL; explicit override before local/remote releases. |
| `GENTLE_CC_REF` | Pinned commit above | Source ref used by `install.sh` with `GENTLE_CC_SOURCE`; ignored for releases. |
| `GENTLE_CC_OWNER_REPO` | `AngelCLA/gentle-ai-cc` | GitHub repository for release downloads in `install.sh` / `install.ps1`. |

## Limitations

- **Not upstream.** Community workaround, not supported by the gentle-ai
  maintainers; no support commitment is established by this repository preparation.
- **Build-from-source needs the full module.** Go's `internal/` rule forbids an
  external module from importing the adapter, so a source build needs the whole
  gentle-ai module. Users installing a **prebuilt release** do not need it.
- **Version skew is inherent.** The companion is built from a branch that may be
  ahead of the installed release; Command Code can receive newer guidance than
  opencode/pi until you rebuild on the same base.
- **Manual client install.** Gentle AI does not install Command Code.
- **MVP scope.** ODD guidance, skills, MCP and ordinary verification — not
  native RDD execution; no managed review hooks or file-subagent projection.
- **State cleanup is load-bearing.** Distributing the wrapper without its
  post-run state cleanup would break the official binary's sync.

## Troubleshooting

- `unsupported agent "command-code"` from the **official** binary: use
  `gentle-cc` for Command Code.
- Official `sync` fails `not supported in MVP`: run any `gentle-cc sync`/`install`
  (it cleans state) or edit `~/.gentle-ai/state.json` manually.
- `python3 required for shared-state cleanup`: you are running the legacy
  `4.3.1-cc.1` wrapper, not the native executable. Install `4.3.1-cc.4` once published or a
  source-built native pair; `--no-wrapper` installs only the companion for the
  legacy release.
- `cannot clean shared state`: inspect and repair `~/.gentle-ai/state.json`;
  invalid existing state is rejected before either mutating binary runs.
- `shared state busy (gentle-cc.lock)`: wait for the active operation (it may
  outlive a killed invoking wrapper). Never delete a regular lock file.
  A legacy **directory** lock has no trustworthy owner metadata. Age or a PID
  alone cannot prove it is safe to remove. For separately authorized manual
  migration, first establish exclusive control: stop all wrapper entry points,
  schedulers and concurrent shells on every host sharing this HOME, and verify
  that all old wrappers, supervisors, and binary children have finished. Only
  while that exclusion remains in force, inspect the path and use `rmdir` on
  the confirmed empty legacy directory (never recursive removal). If quiescence
  cannot be proved, leave it in place. Then let the next wrapper create the OS
  lock file. No real user lock recovery is performed by the tests or installer.
- `OS locking unavailable` / `cannot acquire shared-state OS lock`: use the native
  wrapper on Windows, Linux or macOS with working OS locks and a controlled,
  writable state directory. Do not bypass the lock. Linked state/lock paths or
  hardlinked lock files require investigation, not automatic replacement.
- `checksum mismatch`: the download is corrupted or the manifest is stale — do
  not install; re-fetch from the pinned release.
- Companion build fails: confirm `--ref` exists and Go is on `PATH`.
- Unrelated: an opencode V2 plugin precondition (`@opencode/plugin@2.0.4`) can
  block the official `sync` on some machines; it is not a Command Code issue.
