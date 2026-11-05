# gentle-cc — a reproducible, distributable Command Code companion for gentle-ai

Use the **official `gentle-ai` release** for every supported agent *and* use
**Command Code** (`command-code`), without waiting for upstream to accept a
Command Code adapter. One verified binary; no full repo clone for users.

> Command Code support is **not** upstream. Issues #1913 (approved, then
> `NOT_PLANNED`), #4105 and #5790 were closed under the policy *"we're not
> accepting new agents for now."* This is a community workaround.

## Quick install (no Go, no repo clone)

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
```

That downloads the companion binary for your OS/arch **and** the `gentle-cc`
wrapper, verifies both against `checksums.txt`, and installs them to
`~/.local/bin`. Then:

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
| `install.sh` | One-line convenience wrapper around the installer. |

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

If you already have the official `gentle-ai` installed, there is no conflict: the
official binary manages the other agents, the companion manages `command-code`,
and the wrapper keeps the shared `state.json` compatible (see below). The only
cost of the design is size: the companion is a second full binary (~31 MB), not a
small add-on.

Data the companion writes (same shape as any managed agent):

- `~/.commandcode/AGENTS.md` — managed marker sections (persona, engram
  protocol, orchestrator, agent routing, remote authorization), preserving your
  own content.
- `~/.commandcode/skills/<skill>/SKILL.md` — selected skills.
- `~/.commandcode/mcp.json` — `engram` and `context7` stdio entries.

## Installation options

### A. Prebuilt release (recommended, no Go)

```bash
gentle-cc-install.sh --from-release https://github.com/<owner>/<repo>/releases/download/4.3.1-cc.1
```

### B. Build from source at a pinned commit (needs Go 1.25+)

```bash
gentle-cc-install.sh --from-source https://github.com/<owner>/<repo>.git --ref <pinned-commit>
```

Both install `~/.local/bin/gentle-ai-cc` and, unless `--no-wrapper`,
`~/.local/bin/gentle-cc`.

## Commands

```bash
gentle-cc build             # build the companion from a branch checkout
gentle-cc install [args]    # install only Command Code (companion)
gentle-cc sync    [args]    # refresh only Command Code (companion)
gentle-cc doctor  [args]    # run doctor with the companion binary
gentle-cc sync-all[args]    # official sync for other agents + Command Code
```

## Reproducibility guarantees

- Builds use `-trimpath -buildvcs=false` and inject the version from
  `--version`, so the binary does not depend on the build directory or VCS
  state. Verified: two runs of the same commit produce **byte-identical**
  binaries (identical `sha256` for all six platform artifacts).
- The installer refuses to install when a downloaded artifact's `sha256` does
  not match `checksums.txt` (verified against a tampered manifest).
- Pin the commit (`--ref`) or the release tag in shared instructions so
  everyone gets the same bytes.

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

The companion's `install` records `command-code` there. The wrapper
**automatically removes** `command-code` and the stale `commandcode` from
`installed_agents` after every `install`/`sync`, so the official binary keeps
working. `--dry-run` hides this (it does not build adapters); verify with a real
`sync`.

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
- `checksum mismatch`: the download is corrupted or the manifest is stale — do
  not install; re-fetch from the pinned release.
- Companion build fails: confirm `--ref` exists and Go is on `PATH`.
- Unrelated: an opencode V2 plugin precondition (`@opencode/plugin@2.0.4`) can
  block the official `sync` on some machines; it is not a Command Code issue.
