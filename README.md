# gentle-cc — a reproducible, distributable Command Code companion for gentle-ai

Use the **official `gentle-ai` release** for every supported agent *and* use
**Command Code** (`command-code`), without waiting for upstream to accept a
Command Code adapter. One verified binary; no full repo clone for users.

> Command Code support is **not** upstream. Issues #1913 (approved, then
> `NOT_PLANNED`), #4105 and #5790 were closed under the policy *"we're not
> accepting new agents for now."* This is a community workaround.

## Quick install (no Go, no repo clone of gentle-ai)

This repository is **private**, so use an authenticated clone (not the anonymous
`curl` form):

```bash
git clone https://github.com/AngelCLA/gentle-ai-cc.git
cd gentle-ai-cc && ./install.sh
```

`install.sh` uses a local `dist/` when present, otherwise downloads the release
with your authenticated `gh`, otherwise builds from source if you set
`GENTLE_CC_SOURCE`. It installs the companion binary for your OS/arch **and** the
`gentle-cc` wrapper, verifying both against `checksums.txt`, to `~/.local/bin`.
Then:

```bash
gentle-cc install --preset full-gentleman   # first time
gentle-cc sync                              # subsequent
```

Pin a specific release with `GENTLE_CC_VERSION=4.3.1-cc.1`.

## What this is

The official binary manages opencode / pi / vscode-copilot / etc. A companion
binary built from the branch that carries the Command Code adapter manages
`command-code` only. The wrapper runs the companion for `command-code` and keeps
the shared `state.json` compatible with the official binary.

| File | Role |
| --- | --- |
| `gentle-ai-cc` | Companion binary (has the Command Code adapter). |
| `gentle-cc` | Wrapper: runs the companion only for `command-code`, cleans shared state. |
| `gentle-cc-release.sh` | Builds reproducible per-platform binaries + wrapper + `checksums.txt`. |
| `gentle-cc-install.sh` | Installs verified binaries from a release **or** builds from a pinned commit. |
| `install.sh` | POSIX convenience installer (clone-based; private-repo safe). |
| `install.ps1` | Windows installer (PowerShell; verified download). |

## Platform support

| OS / arch | Companion binary | Installer | Wrapper (`gentle-cc`) |
| --- | --- | --- | --- |
| Linux amd64 / arm64 | Yes | `install.sh` | Yes (bash) |
| macOS amd64 / arm64 | Yes | `install.sh` | Yes (bash) |
| Windows amd64 / arm64 | Yes | `install.ps1` | **No** — bash script |

On **Linux/macOS** the full flow (`install.sh` → `gentle-cc install/sync`) works
as documented. Mutating wrapper commands also require **Python 3** on `PATH`
with `fcntl.flock` (for OS locking, shared-state validation and atomic cleanup);
release users do not need Go. Linux fixture tests exercise the lock; macOS uses
the same POSIX API but has not been runtime-verified in this environment.

On **Windows**, use `install.ps1` to install the companion binary, then call the
binary directly:

```powershell
gentle-ai-cc.exe install --agent command-code --preset full-gentleman
gentle-ai-cc.exe sync --agent command-code
```

The `gentle-cc` wrapper is a **bash** script (it does the `state.json` cleanup
after each operation). **Git Bash is not a supported mutating wrapper runtime**:
native Windows Python generally lacks `fcntl.flock`. Missing or unusable OS locking
fails closed, before either mutating binary runs; there is no mkdir fallback.
WSL with Linux Bash/Python uses the Linux locking path (not runtime-verified here).
Without a supported wrapper runtime, call the companion directly and note that the wrapper's
post-run state cleanup will not happen (see "The shared-state detail").
`install.ps1` uses local `dist/` only when both the requested version/platform
asset and its checksum entry are present. Otherwise it downloads via `gh` into
fresh temporary staging, never using `dist/` as a download cache. A native `gh`
failure or checksum mismatch aborts installation; owned staging is cleaned on
success and failure. A complete but corrupt local release fails checksum
verification rather than silently falling back to a download.
`install.ps1` was not executed in this environment (no PowerShell available);
run the fixture checks below before relying on it.

## Do I need the gentle-ai repo or the official binary?

**No.** The companion (`gentle-ai-cc`) is a **complete gentle-ai binary**: the same
program compiled from the branch that also carries the Command Code adapter. It is
not a plugin and does not load the official binary or the project source at run
time.

Verified: `gentle-ai-cc install --agent command-code` succeeds in a clean `HOME`
with no official `gentle-ai` on `PATH` and no checkout present.

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

### A. Prebuilt release (recommended, no Go)

```bash
gentle-cc-install.sh --from-release https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.1
```

### B. Build from source at a pinned commit (needs Go 1.25+)

This builds the **gentle-ai** module, so `--from-source` must point at a checkout
of gentle-ai that contains the Command Code adapter (a fork/branch with
`internal/agents/commandcode/`). It does **not** work against this distribution
repo, which contains scripts only.

The wrapper comes from **this distribution**, beside `gentle-cc-install.sh`,
not from the external gentle-ai module. Keep the installer and `gentle-cc` from
this distribution together so their versions remain coherent. Source mode checks
and stages that wrapper before creating or changing the destination and before
cloning or building. If it is unavailable, installation fails without replacing
an existing binary or wrapper; it never silently keeps an old wrapper or reports
success with a missing one. Use `--no-wrapper` to explicitly install only the
binary without needing the distribution wrapper (any existing wrapper is left
unchanged). Both Bash modes use the publication recovery described below.

```bash
gentle-cc-install.sh --from-source https://github.com/<you>/gentle-ai.git --ref <pinned-commit>
```

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
on Linux/macOS, **not** the separate Windows PowerShell installer.
Authenticated `install.sh` downloads clean their staging on both child success
and failure, preserving the child's exit status.

## Commands

```bash
gentle-cc build             # build the companion from a branch checkout
gentle-cc install [args]    # install only Command Code (companion)
gentle-cc sync    [args]    # refresh only Command Code (companion)
gentle-cc doctor  [args]    # run doctor with the companion binary
gentle-cc sync-all[args]    # official sync for other agents + Command Code
```

### Wrapper-owned agent selection

`sync`, `install`, and `sync-all` reject every user token named `--agent`,
`-agent`, `--agents`, or `-agents`, bare or with `=value`, including empty values,
repeated selectors, and attempts to select `command-code` itself.
This also applies with any help alias, dry-run,
and after `--`. Rejection occurs before Python/state preflight, locking, builds,
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

## Reproducibility guarantees

- Builds use `-trimpath -buildvcs=false` and inject the version from
  `--version`, so the binary does not depend on the build directory or VCS
  state. Verified: two runs of the same commit produce **byte-identical**
  binaries (identical `sha256` for all six platform artifacts).
- The installer refuses to install when a downloaded artifact's `sha256` does
  not match `checksums.txt` (verified against a tampered manifest).
- Pin the commit (`--ref`) or the release tag in shared instructions so
  everyone gets the same bytes.

## Installer regression checks

Run isolated fixture tests (no real releases, Go builds, or installs into your
home directory):

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
bash -n gentle-cc-install.sh install.sh
```

The Python suite runs `tests/installers.ps1` when `pwsh` or `powershell` is on
`PATH`, and reports a skip otherwise. You can also run it directly:

```powershell
pwsh -NoProfile -File tests/installers.ps1
```

The PowerShell fixtures use fake `gh` downloads and temporary destinations to
check local/version selection, checksum and native-command failures, unchanged
local artifacts, and staging cleanup.

## Publishing a release (for the maintainer)

1. Keep the branch rebased on `origin/main` so guidance does not drift behind
   the official release.
2. Build artifacts (binaries + wrapper + manifest):

   ```bash
   ./gentle-cc-release.sh --repo ~/dev/gentle-ai --version 4.3.1-cc.1 --out dist
   ```

3. Publish them under a tag matching `--version`:

   ```bash
   gh release create 4.3.1-cc.1 dist/* --title 4.3.1-cc.1 --notes "Command Code companion 4.3.1-cc.1"
   ```

4. Share the `--from-release` URL / the one-line `install.sh`.
5. On each new upstream release: rebase, bump `--version`, rebuild, re-upload,
   update the pinned `--ref`/tag.

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
stale `commandcode` from `installed_agents`, preserving other agents and JSON
fields. Cleanup writes a temporary file in the same directory, preserves the
file mode, flushes and fsyncs the file, then atomically replaces `state.json`.
Already-open readers retain the old file; this does not make the companion's
own writes atomic or promise durability across every filesystem/power failure.

Before invoking a mutating binary, the wrapper checks for Python 3 and validates
existing state (a JSON object with an optional `installed_agents` list of
strings). Missing state is allowed; malformed JSON, invalid schema and I/O
errors are reported rather than silently ignored. A companion failure retains
its exit status if cleanup succeeds; a cleanup failure returns an error instead.

A persistent regular file at `~/.gentle-ai/gentle-cc.lock`, locked with Python's
`fcntl.flock`, serializes wrapper mutations, including the **entire** `sync-all`
operation and cleanup. A held lock or a legacy directory lock fails immediately:
`gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions`.
Exit status is 1, stdout is empty, and shared state and binaries are untouched.
Missing `fcntl.flock` reports exactly
`gentle-cc: OS locking unavailable; requires Python 3 fcntl.flock on Linux/macOS`;
other lock acquisition errors also fail closed. Filesystem support is required;
use a locally controlled filesystem with working advisory locks.

The lock file remains after completion: **never unlink, replace, or recreate it**,
even when idle (doing so splits contenders across different inodes). An independent
Python supervisor retains the lock until the foreground operation shell exits;
that shell also inherits the locked descriptor. Killing the invoking wrapper
alone with SIGKILL does not free the lock while its operation continues. SIGTERM
and SIGINT are forwarded to the operation's process group; the supervisor retains
the lock while the shell waits for its foreground binary, even if that binary
ignores termination. Normal exit releases the OS lock without deleting the file.
A killed invocation may leave state needing cleanup; OS lock release is not a
transaction or automatic state repair. Daemonized/background writers, deliberate
closure of inherited descriptors, and killing the whole supervisor/operation tree
are outside this guarantee. Do not use binaries that leave background writers.
No recovery or lock migration runs automatically.

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
wins**, including mixed hyphens: `--dry-run -dry-run=false` requires Python,
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
`sync-all` still needs Python to read the other-agent list.
Dry-run can hide unsupported-agent errors because it does not build adapters;
verify compatibility with a real `sync`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `GENTLE_CC_REPO` | `~/dev/gentle-ai` | Branch checkout used to build the companion. |
| `GENTLE_CC_BIN` | `~/.local/bin/gentle-ai-cc` | Companion binary path. |
| `GENTLE_AI_BIN` | `gentle-ai` | Official binary used by `sync-all`. |
| `GENTLE_CC_DEST` | `~/.local/bin` | Where the installer writes binaries. |
| `GENTLE_CC_VERSION` | `4.3.1-cc.1` | Release tag used by `install.sh`. |

## Limitations

- **Not upstream.** Maintained by whoever publishes it; not supported by the
  gentle-ai maintainers.
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
- `python3 required for shared-state cleanup`: install Python 3 and ensure it is
  on `PATH` before running a mutating wrapper command.
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
- `OS locking unavailable` / `cannot acquire shared-state OS lock`: use supported
  Linux/macOS Bash and Python 3 with working `fcntl.flock`; do not bypass the lock.
- `checksum mismatch`: the download is corrupted or the manifest is stale — do
  not install; re-fetch from the pinned release.
- Companion build fails: confirm `--ref` exists and Go is on `PATH`.
- Unrelated: an opencode V2 plugin precondition (`@opencode/plugin@2.0.4`) can
  block the official `sync` on some machines; it is not a Command Code issue.
