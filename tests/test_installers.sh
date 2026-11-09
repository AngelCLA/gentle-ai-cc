#!/usr/bin/env bash
# Public-interface installer fixtures. Bash + standard tools only; no network,
# real builds, companion execution, user configuration, or Python interpreter.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PATH="$PATH"
SUITE="$(mktemp -d)"
trap 'rm -rf -- "$SUITE"' EXIT
unset GENTLE_CC_SOURCE GENTLE_CC_REF GENTLE_CC_VERSION GENTLE_CC_OWNER_REPO
passed=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: expected [$2], got [$1]"; }
bytes() { cmp -s "$1" "$2" || fail "different bytes: $1 / $2"; }
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
hash() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
empty_stage() {
  local entries
  entries="$(find "$TMPDIR" -mindepth 1 -print)"
  eq "$entries" '' 'temporary staging cleanup'
}
# Compare names, bytes and modes, including hidden publication directories.
snapshot() {
  local path
  (cd "$GENTLE_CC_DEST" && find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r path; do
    printf '%s %s ' "$path" "$(mode "$path")"
    if [ -f "$path" ]; then hash "$path"; else printf 'non-file\n'; fi
  done)
}
preserved() { eq "$(snapshot)" "$(< "$F/before")" 'destination preservation'; empty_stage; }
executable() {
  if [ "$MODES" = supported ]; then [ -x "$1" ] || fail "not executable: $1"; fi
}
manifest() {
  { printf '%s  %s\n' "$(hash "$F/new-binary")" "$asset"
    if [ "${1:-both}" = both ]; then printf '%s  %s\n' "$(hash "$F/new-wrapper")" "$wrapper_asset"; fi
  } > "$F/release/checksums.txt"
}
fixture() {
  F="$(mktemp -d "$SUITE/case.XXXXXXXX")"
  export HOME="$F/home" TMPDIR="$F/tmp" GENTLE_CC_DEST="$F/bin"
  export TOOL_LOG="$F/tool-log" TRANSPORT_LOG="$F/transport-log"
  export FIXTURE_SOURCE="$F/external module with spaces"
  export FIXTURE_DISTRIBUTION="$F/distribution with spaces"
  export FIXTURE_RELEASE="$F/release"
  export FAIL_COUNT="$F/failure-count" FAIL_KIND='' FAIL_AT=0 FAIL_RESTORE=0 CHANGE_DISTRIBUTION=0
  mkdir -p "$HOME" "$TMPDIR" "$GENTLE_CC_DEST" "$F/release" "$F/tools" "$FIXTURE_SOURCE" "$FIXTURE_DISTRIBUTION"
  cp "$ROOT/gentle-cc-install.sh" "$FIXTURE_DISTRIBUTION/"
  mkdir -p "$FIXTURE_DISTRIBUTION/cmd/gentle-cc"
  cp "$ROOT/go.mod" "$FIXTURE_DISTRIBUTION/go.mod"
  cp "$ROOT/cmd/gentle-cc/main.go" "$FIXTURE_DISTRIBUTION/cmd/gentle-cc/main.go"
  printf 'new binary\n' > "$F/new-binary"
  printf 'new wrapper\n' > "$F/new-wrapper"
  cp "$F/new-binary" "$F/release/$asset"
  cp "$F/new-wrapper" "$F/release/$wrapper_asset"
  manifest
  printf 'old gentle-ai-cc' > "$GENTLE_CC_DEST/gentle-ai-cc"
  printf 'old gentle-cc' > "$GENTLE_CC_DEST/gentle-cc"
  chmod 640 "$GENTLE_CC_DEST/"*
  snapshot > "$F/before"
  cp -p "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
  cp -p "$GENTLE_CC_DEST/gentle-ai-cc" "$F/old-binary"
  # Curl never reaches the network; accept exactly the public installer's API.
  cat > "$F/tools/curl" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" = 4 ] && [ "$1" = -fsSL ] && [ "$3" = -o ] || exit 90
case "$2" in
    file://*) source=${2#file://} ;;
    https://github.com/*/releases/download/*/*) source="$FIXTURE_RELEASE/${2##*/}" ;;
    *) exit 91 ;;
  esac
printf '%s\n' "${source##*/}" >> "$TRANSPORT_LOG"
[ -f "$source" ] || exit 22
cp "$source" "$4"
TOOL
  cat > "$F/tools/git" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$1" >> "$TOOL_LOG"
case "$1" in
  clone)
    mkdir -p "$4"
    if [ -f "$FIXTURE_SOURCE/gentle-cc" ]; then cp "$FIXTURE_SOURCE/gentle-cc" "$4/gentle-cc"; fi
    if [ "$CHANGE_DISTRIBUTION" = 1 ]; then printf 'changed during clone\n' > "$FIXTURE_DISTRIBUTION/gentle-cc"; fi ;;
  checkout) ;;
  *) exit 90 ;;
esac
TOOL
  cat > "$F/tools/go" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = build ] || exit 91
[ "$2" = -trimpath ] && [ "$3" = -buildvcs=false ] && [ "$4" = -ldflags ] || exit 96
case "$5" in '-s -w -X main.version='*) ;; *) exit 97 ;; esac
[ "$CGO_ENABLED" = 0 ] || exit 98
output=''; target="${!#}"
case "$target" in
  ./cmd/gentle-cc) [ "$PWD" = "$FIXTURE_DISTRIBUTION" ] || exit 93; content=wrapper ;;
  ./cmd/gentle-ai) case "$PWD" in */src|"$FIXTURE_SOURCE") ;; *) exit 94 ;; esac; content=binary ;;
  *) exit 95 ;;
esac
printf 'go build %s %s/%s\n' "$target" "$GOOS" "$GOARCH" >> "$TOOL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then output="$2"; shift; fi
  shift
done
printf 'new %s\n' "$content" > "$output"
TOOL
  chmod +x "$F/tools/"*
  printf '#!/usr/bin/env bash\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac\n' > "$F/tools/uname"
  chmod +x "$F/tools/uname"
  export PATH="$F/tools:$BASE_PATH"
}
run() {
  status=0
  (cd "$HOME" && bash "$@") > "$F/stdout" 2> "$F/stderr" || status=$?
}
release() { run "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh" --from-release "file://$F/release" "$@"; }
source_install() { run "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh" --from-source "$FIXTURE_SOURCE" --ref fixture-ref "$@"; }
platform_line() { printf 'platform: %s/%s  asset: %s\n' "$os" "$arch" "$asset"; }
release_prefix() {
  platform_line
  printf 'downloading %s ...\nchecksum OK (%s): %s\n' "$asset" "$asset" "$(hash "$F/new-binary")"
  if [ "${1:-both}" = both ]; then
    printf 'downloading gentle-cc wrapper ...\nchecksum OK (%s): %s\n' "$wrapper_asset" "$(hash "$F/new-wrapper")"
  fi
}
source_prefix() {
  platform_line
  printf 'cloning %s ...\nbuilding at fixture-ref (reproducible) ...\n' "$FIXTURE_SOURCE"
}
success_tail() {
  printf 'installed: %s/gentle-ai-cc\n' "$GENTLE_CC_DEST"
  if [ "${1:-guidance}" = guidance ]; then
    printf '\nnext:\n  %s/gentle-ai-cc version\n  %s/gentle-cc install --preset full-gentleman   # or: %s/gentle-cc sync\n' "$GENTLE_CC_DEST" "$GENTLE_CC_DEST" "$GENTLE_CC_DEST"
  fi
}
output_is() { bytes "$F/stdout" "$F/expected-out"; bytes "$F/stderr" "$F/expected-err"; }
expected_error() { printf 'install: %s\n' "$1" > "$F/expected-err"; }
check_source_success() {
  eq "$status" 0 'source exit'
  { source_prefix; printf 'built SHA256: %s\n' "$(hash "$F/new-binary")"; success_tail "${1:-guidance}"; } > "$F/expected-out"
  : > "$F/expected-err"
  output_is
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"
  executable "$GENTLE_CC_DEST/gentle-ai-cc"
  empty_stage
}

# Public installer help migrated from the legacy Python help suite. Pin the
# current native names and guidance independently of the production comment block.
installer_help_expected() {
  cat <<'HELP'
# gentle-cc-install.sh — checksum-verifying installer for the Command Code
# companion of gentle-ai.
#
# Two modes:
#
#   --from-release URL_PREFIX
#       Download the prebuilt binary for this OS/arch and the wrapper from
#       URL_PREFIX, and verify both against checksums.txt in the same prefix.
#       No Go required.
#       Example: --from-release file:///path/to/prepared/native-release --version V
#
#   --from-source GIT_URL [--ref REF]
#       Clone/checkout GIT_URL at REF (default the pinned commit) and build the
#       companion with reproducibility flags. Build the native wrapper from this
#       distribution's Go module, never from GIT_URL, before destination changes.
#       The pinned source currently requires Go 1.25.10 or newer.
#       A missing distribution Go module is an error unless --no-wrapper is given.
#       Native assets: gentle-cc_<version>_<os>_<arch>[.exe], not legacy gentle-cc.
#       4.3.1-cc.5 is the native release default; 4.3.1-cc.1 is the legacy wrapper.
#
# Options:
#   --ref REF       Source commit/tag (default the pinned commit).
#   --version V     Release asset version / source build version (default 4.3.1-cc.5).
#   --no-wrapper    Install only the binary; leave any existing wrapper unchanged.
#   --sha-only      Still installs; suppresses final next-step guidance only.
# GENTLE_CC_DEST overrides the default destination below; it does not update PATH.
#
# Both modes install:
#   ~/.local/bin/gentle-ai-cc     (companion binary; .exe on Windows)
#   ~/.local/bin/gentle-cc        (native wrapper; .exe on Windows, unless --no-wrapper)
# Controlled publication errors restore this invocation's changed files only.
# Not an atomic pair or crash/signal-safe; see README for recovery limitations.
HELP
}
assert_installer_help() {
  eq "$status" 0 'installer help exit'
  output_is
  eq "$(find "$HOME" -mindepth 1 -print)" "$HOME/keep" 'help leaves HOME untouched'
  bytes "$HOME/keep" "$F/expected-keep"
  [ ! -e "$TOOL_LOG" ] || fail 'help invoked build tools'
  [ ! -e "$TRANSPORT_LOG" ] || fail 'help invoked transport'
  preserved
}
installer_help_checks() {
  local preceding
  for preceding in no yes; do
    fixture
    printf 'unchanged\n' > "$F/expected-keep"
    cp "$F/expected-keep" "$HOME/keep"
    installer_help_expected > "$F/expected-out"
    : > "$F/expected-err"
    if [ "$preceding" = no ]; then
      run "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh" --help
    else
      run "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh" --from-source unused \
        --ref unused-ref --version unused-version --no-wrapper --sha-only --help
    fi
    assert_installer_help
    passed=$((passed + 1))
  done
}

# Transport/build fixtures are platform-independent bytes. Pin the Unix matrix;
# a separate Windows selection case below checks native executable names.
os=linux; arch=amd64; ext=''
version='4.3.1-cc.5'
asset="gentle-ai-cc_${version}_${os}_${arch}${ext}"
wrapper_asset="gentle-cc_${version}_${os}_${arch}${ext}"
installer_help_checks
printf 'mode probe\n' > "$SUITE/mode-probe"
chmod 640 "$SUITE/mode-probe"
MODES=supported
if [ "$(mode "$SUITE/mode-probe")" != 640 ] || [ -x "$SUITE/mode-probe" ]; then
  MODES=unsupported
else
  chmod 750 "$SUITE/mode-probe"
  [ "$(mode "$SUITE/mode-probe")" = 750 ] && [ -x "$SUITE/mode-probe" ] || MODES=unsupported
fi
if [ "$MODES" = unsupported ]; then
  printf 'LIMITATION: host filesystem does not enforce POSIX modes; executable-bit certification skipped (bytes and observed modes still compared).\n'
fi

# RED: a private, deliberately wrong installer must fail the public byte check.
# No history dependency and no production edits. Keep the failure log until teardown.
fixture
mutant="$(< "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh")"
mutant=${mutant/'publish_artifacts "$tmp/$BIN_NAME"'/'printf "wrong wrapper\n" > "$tmp/$WRAPPER_NAME"; publish_artifacts "$tmp/$BIN_NAME"'}
printf '%s\n' "$mutant" > "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh"
source_install
red_status=0
(bytes "$GENTLE_CC_DEST/gentle-cc" "$F/new-wrapper") > "$F/red-log" 2>&1 || red_status=$?
eq "$red_status" 1 'deliberate mutant detection exit'
printf 'RED: isolated wrong-wrapper installer exit=%s; assertion exit=%s; %s\n' "$status" "$red_status" "$(< "$F/red-log")"

# test_validation_failures_preserve_both_destinations
for failure in wrapper-mismatch wrapper-missing wrapper-entry binary-mismatch binary-entry; do
  fixture
  release_prefix > "$F/expected-out"
  case "$failure" in
    wrapper-mismatch)
      printf tampered > "$F/release/$wrapper_asset"
      expected_error "checksum mismatch for $wrapper_asset: expected $(hash "$F/new-wrapper") got $(hash "$F/release/$wrapper_asset")"
      # The verification line for the wrapper must not have been printed.
      { platform_line; printf 'downloading %s ...\nchecksum OK (%s): %s\ndownloading gentle-cc wrapper ...\n' "$asset" "$asset" "$(hash "$F/new-binary")"; } > "$F/expected-out" ;;
    wrapper-missing|wrapper-entry)
      if [ "$failure" = wrapper-missing ]; then
        mv "$F/release/$wrapper_asset" "$F/removed-wrapper"
        expected_error 'wrapper download failed'
      else manifest binary; expected_error "no checksum entry for $wrapper_asset"; fi
      { platform_line; printf 'downloading %s ...\nchecksum OK (%s): %s\ndownloading gentle-cc wrapper ...\n' "$asset" "$asset" "$(hash "$F/new-binary")"; } > "$F/expected-out" ;;
    binary-mismatch|binary-entry)
      if [ "$failure" = binary-mismatch ]; then
        printf tampered > "$F/release/$asset"
        expected_error "checksum mismatch for $asset: expected $(hash "$F/new-binary") got $(hash "$F/release/$asset")"
      else : > "$F/release/checksums.txt"; expected_error "no checksum entry for $asset"; fi
      { platform_line; printf 'downloading %s ...\n' "$asset"; } > "$F/expected-out" ;;
  esac
  release
  eq "$status" 1 "$failure exit"; output_is; preserved
  passed=$((passed + 1))
done

# test_success_installs_both_executable_artifacts / test_no_wrapper_does_not_request_wrapper_and_sha_only_still_installs
for requested in both binary; do
  fixture
  if [ "$requested" = both ]; then release; else
    mv "$F/release/$wrapper_asset" "$F/removed-wrapper"; manifest binary
    release --no-wrapper --sha-only
  fi
  eq "$status" 0 'release exit'
  { release_prefix "$requested"; if [ "$requested" = both ]; then success_tail; else success_tail quiet; fi; } > "$F/expected-out"
  : > "$F/expected-err"; output_is
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"; executable "$GENTLE_CC_DEST/gentle-ai-cc"
  if [ "$requested" = both ]; then
    bytes "$GENTLE_CC_DEST/gentle-cc" "$F/new-wrapper"; executable "$GENTLE_CC_DEST/gentle-cc"
  else
    bytes "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
    eq "$(mode "$GENTLE_CC_DEST/gentle-cc")" "$(mode "$F/old-wrapper")" 'unrequested wrapper mode'
  fi
  { printf 'checksums.txt\n%s\n' "$asset"; [ "$requested" != both ] || printf '%s\n' "$wrapper_asset"; } > "$F/expected-transport"
  bytes "$TRANSPORT_LOG" "$F/expected-transport"; empty_stage
  passed=$((passed + 1))
done

# Published checksums.txt uses CRLF line endings; its assets must still verify.
fixture
awk '{ printf "%s\r\n", $0 }' "$F/release/checksums.txt" > "$F/checksums-crlf"
mv "$F/checksums-crlf" "$F/release/checksums.txt"
release
eq "$status" 0 'CRLF release manifest exit'
{ release_prefix; success_tail; } > "$F/expected-out"
: > "$F/expected-err"; output_is
bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"
bytes "$GENTLE_CC_DEST/gentle-cc" "$F/new-wrapper"
empty_stage
passed=$((passed + 1))

# Asset names are literal, including SemVer build metadata and binary markers.
(
  version='1.0.0+build.1'
  asset="gentle-ai-cc_${version}_${os}_${arch}${ext}"
  wrapper_asset="gentle-cc_${version}_${os}_${arch}${ext}"
  fixture
  printf '%s *%s\r\n%s *%s\r\n' "$(hash "$F/new-binary")" "$asset" \
    "$(hash "$F/new-wrapper")" "$wrapper_asset" > "$F/release/checksums.txt"
  release --version "$version"
  eq "$status" 0 'literal build metadata release exit'
  { release_prefix; success_tail; } > "$F/expected-out"
  : > "$F/expected-err"; output_is
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"
  bytes "$GENTLE_CC_DEST/gentle-cc" "$F/new-wrapper"
  executable "$GENTLE_CC_DEST/gentle-ai-cc"
  executable "$GENTLE_CC_DEST/gentle-cc"
  printf 'checksums.txt\n%s\n%s\n' "$asset" "$wrapper_asset" > "$F/expected-transport"
  bytes "$TRANSPORT_LOG" "$F/expected-transport"
  empty_stage
)
passed=$((passed + 1))

# Source wrapper must build from this distribution module, never external bytes.
for external in present absent; do
  fixture
  if [ "$external" = present ]; then printf 'external wrapper\n' > "$FIXTURE_SOURCE/gentle-cc"; fi
  source_install; check_source_success
  bytes "$GENTLE_CC_DEST/gentle-cc" "$F/new-wrapper"; executable "$GENTLE_CC_DEST/gentle-cc"
  printf 'git clone\ngit checkout\ngo build ./cmd/gentle-cc linux/amd64\ngo build ./cmd/gentle-ai linux/amd64\n' > "$F/expected-tools"
  bytes "$TOOL_LOG" "$F/expected-tools"
  passed=$((passed + 1))
done
for existing in yes no; do
  fixture
  mv "$FIXTURE_DISTRIBUTION/go.mod" "$F/removed-module"
  if [ "$existing" = no ]; then export GENTLE_CC_DEST="$F/not created destination"; fi
  source_install; eq "$status" 1 'missing distribution module exit'
  : > "$F/expected-out"; expected_error "source wrapper unavailable: $FIXTURE_DISTRIBUTION/go.mod"; output_is
  if [ "$existing" = yes ]; then preserved; else [ ! -e "$GENTLE_CC_DEST" ] || fail 'destination created'; fi
  [ ! -e "$TOOL_LOG" ] || fail 'tools ran before module preflight'; empty_stage
  passed=$((passed + 1))
done
for existing in yes no; do
  fixture
  mv "$FIXTURE_DISTRIBUTION/go.mod" "$F/removed-module"
  if [ "$existing" = no ]; then mv "$GENTLE_CC_DEST/gentle-cc" "$F/removed-wrapper"; fi
  source_install --no-wrapper --sha-only; check_source_success quiet
  printf 'git clone\ngit checkout\ngo build ./cmd/gentle-ai linux/amd64\n' > "$F/expected-tools"
  bytes "$TOOL_LOG" "$F/expected-tools"
  if [ "$existing" = yes ]; then
    bytes "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
    eq "$(mode "$GENTLE_CC_DEST/gentle-cc")" "$(mode "$F/old-wrapper")" 'unrequested wrapper mode'
  else [ ! -e "$GENTLE_CC_DEST/gentle-cc" ] || fail 'wrapper unexpectedly installed'; fi
  passed=$((passed + 1))
done

publication_faults() {
  local tool real
  for tool in cp chmod mv mktemp rm; do
    real="$(PATH="$BASE_PATH" command -v "$tool")"
    { printf '#!/usr/bin/env bash\nREAL=%q\nTOOL=%q\n' "$real" "$tool"
      cat <<'TOOL'
if [ "$TOOL" = rm ] && [ "$*" = "-f $GENTLE_CC_DEST/gentle-ai-cc" ] && [ "$FAIL_RESTORE" = 1 ]; then exit 74; fi
case "$*" in
  *"$GENTLE_CC_DEST/.gentle-cc-install."*)
    kind=''
    case "$TOOL:$*" in
      mktemp:*) kind=stage-directory ;;
      cp:*'/new-'*) kind=stage ;;
      cp:*'/old-'*) kind=snapshot ;;
      chmod:*) kind=permissions ;;
      mv:*'/old-'*) kind=restore ;;
      mv:*) kind=rename ;;
    esac
    if [ "$kind" = "$FAIL_KIND" ]; then
      count=0
      [ ! -f "$FAIL_COUNT" ] || read -r count < "$FAIL_COUNT"
      count=$((count + 1)); printf '%s\n' "$count" > "$FAIL_COUNT"
      [ "$count" != "$FAIL_AT" ] || exit 73
    fi
    if [ "$kind" = restore ] && [ "$FAIL_RESTORE" = 1 ]; then exit 74; fi ;;
esac
exec "$REAL" "$@"
TOOL
    } > "$F/tools/$tool"
    chmod +x "$F/tools/$tool"
  done
}
# test_publication_failures_restore_only_requested_artifacts: full original matrix.
for install_mode in release source; do
  for existing in yes no; do
    for requested in both binary; do
      for kind in stage-directory stage permissions rename snapshot; do
        [ "$kind" != snapshot ] || [ "$existing" = yes ] || continue
        for occurrence in 1 2; do
          if [ "$occurrence" = 2 ] && { [ "$requested" = binary ] || [ "$kind" = stage-directory ]; }; then continue; fi
          fixture
          if [ "$existing" = no ]; then
            mv "$GENTLE_CC_DEST/gentle-ai-cc" "$F/removed-binary"
            if [ "$requested" = both ]; then mv "$GENTLE_CC_DEST/gentle-cc" "$F/removed-wrapper"; fi
          fi
          printf 'keep me' > "$GENTLE_CC_DEST/unrelated"; chmod 604 "$GENTLE_CC_DEST/unrelated"
          snapshot > "$F/before"
          publication_faults; export FAIL_KIND="$kind" FAIL_AT="$occurrence"
          args=(); [ "$requested" = both ] || args=(--no-wrapper)
          if [ "$install_mode" = release ]; then release "${args[@]}"; release_prefix "$requested" > "$F/expected-out"
          else source_install "${args[@]}"; source_prefix > "$F/expected-out"; fi
          name=gentle-ai-cc; [ "$occurrence" = 1 ] || name=gentle-cc
          case "$kind" in
            stage-directory) message='cannot create publication staging' ;;
            stage) message="cannot stage $name" ;;
            permissions) message="cannot set permissions for $name" ;;
            rename) message="cannot replace $name" ;;
            snapshot) message="cannot snapshot $name" ;;
          esac
          eq "$status" 1 "$install_mode/$existing/$requested/$kind/$occurrence exit"
          expected_error "$message"; output_is; preserved
          passed=$((passed + 1))
        done
      done
    done
  done
done

# Restoration failures must retain recovery evidence, not silently claim rollback.
for install_mode in release source; do
  fixture
  if [ "$install_mode" = source ]; then mv "$GENTLE_CC_DEST/gentle-ai-cc" "$F/removed-binary"; fi
  printf unchanged > "$GENTLE_CC_DEST/unrelated"; chmod 600 "$GENTLE_CC_DEST/unrelated"
  cp -p "$GENTLE_CC_DEST/unrelated" "$F/old-unrelated"
  publication_faults; export FAIL_KIND=rename FAIL_AT=2 FAIL_RESTORE=1
  if [ "$install_mode" = release ]; then release; release_prefix > "$F/expected-out"
  else source_install; source_prefix > "$F/expected-out"; fi
  eq "$status" 1 'restoration failure exit'
  recovery=("$GENTLE_CC_DEST"/.gentle-cc-install.*)
  eq "${#recovery[@]}" 1 'one retained backup directory'
  [ -d "${recovery[0]}" ] || fail 'missing recovery directory'
  printf 'install: restoration failed for %s/gentle-ai-cc\ninstall: backups retained at %s; manual recovery required\ninstall: cannot replace gentle-cc\n' "$GENTLE_CC_DEST" "${recovery[0]}" > "$F/expected-err"
  output_is
  if [ "$install_mode" = release ]; then
    bytes "${recovery[0]}/old-gentle-ai-cc" "$F/old-binary"
    eq "$(mode "${recovery[0]}/old-gentle-ai-cc")" "$(mode "$F/old-binary")" 'backup mode'
  else [ ! -e "${recovery[0]}/old-gentle-ai-cc" ] || fail 'unexpected binary backup'; fi
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"
  bytes "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
  eq "$(mode "$GENTLE_CC_DEST/gentle-cc")" "$(mode "$F/old-wrapper")" 'wrapper preservation mode'
  bytes "$GENTLE_CC_DEST/unrelated" "$F/old-unrelated"
  eq "$(mode "$GENTLE_CC_DEST/unrelated")" "$(mode "$F/old-unrelated")" 'unrelated mode'
  empty_stage; passed=$((passed + 1))
done

# Git Bash ln may copy instead of creating a link. State that limitation explicitly.
for kind in symlink directory; do
  fixture
  mv "$GENTLE_CC_DEST/gentle-cc" "$F/removed-wrapper"
  printf 'do not follow' > "$F/target"
  if [ "$kind" = symlink ]; then
    if ! ln -s "$F/target" "$GENTLE_CC_DEST/gentle-cc" || [ ! -L "$GENTLE_CC_DEST/gentle-cc" ]; then
      printf 'LIMITATION: host cannot create real symlinks; symlink destination rejection not certified.\n'
      continue
    fi
  else mkdir "$GENTLE_CC_DEST/gentle-cc"; fi
  release; eq "$status" 1 'unsafe destination exit'
  release_prefix > "$F/expected-out"; expected_error "unsafe destination: $GENTLE_CC_DEST/gentle-cc"; output_is
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/old-binary"
  eq "$(mode "$GENTLE_CC_DEST/gentle-ai-cc")" "$(mode "$F/old-binary")" 'binary mode preservation'
  eq "$(< "$F/target")" 'do not follow' 'link target preservation'
  if [ "$kind" = symlink ]; then [ -L "$GENTLE_CC_DEST/gentle-cc" ] || fail 'link replaced'
  else [ -d "$GENTLE_CC_DEST/gentle-cc" ] || fail 'directory replaced'; fi
  eq "$(find "$GENTLE_CC_DEST" -name '.gentle-cc-install.*' -print)" '' 'no publication staging'
  empty_stage; passed=$((passed + 1))
done

# test_authenticated_child_status_output_and_cleanup (no actual gh download).
for child_status in 0 37; do
  fixture
  cp "$ROOT/install.sh" "$FIXTURE_DISTRIBUTION/install.sh"
  cat > "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh" <<'CHILD'
#!/usr/bin/env bash
printf 'child stdout\n'
printf 'child stderr\n' >&2
exit "$CHILD_STATUS"
CHILD
  printf '#!/usr/bin/env bash\nexit 0\n' > "$F/tools/gh"
  chmod +x "$F/tools/gh" "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh"
  export CHILD_STATUS="$child_status" GENTLE_CC_OWNER_REPO=fixture/repo
  run "$FIXTURE_DISTRIBUTION/install.sh"
  eq "$status" "$child_status" 'authenticated child status'
  printf 'downloading release %s from fixture/repo via gh ...\nchild stdout\n' "$version" > "$F/expected-out"
  printf 'child stderr\n' > "$F/expected-err"
  output_is; preserved; passed=$((passed + 1))
done
# gh absent or unauthenticated: the public HTTPS URL needs no authentication.
fixture
unset GENTLE_CC_OWNER_REPO
printf '#!/usr/bin/env bash\ncase "$1" in auth) exit 1 ;; *) exit 90 ;; esac\n' > "$F/tools/gh"
chmod +x "$F/tools/gh"
cp "$ROOT/install.sh" "$FIXTURE_DISTRIBUTION/install.sh"
run "$FIXTURE_DISTRIBUTION/install.sh" --no-wrapper --sha-only
eq "$status" 0 'public release exit'
{ printf 'downloading release %s from https://github.com/AngelCLA/gentle-ai-cc/releases/download/%s ...\n' "$version" "$version"
  release_prefix binary; success_tail quiet; } > "$F/expected-out"
: > "$F/expected-err"; output_is
bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/new-binary"
bytes "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
empty_stage; passed=$((passed + 1))
# A missing public release keeps the destination intact and honors the mirror override.
fixture
export GENTLE_CC_OWNER_REPO=fixture/mirror
printf '#!/usr/bin/env bash\ncase "$1" in auth) exit 1 ;; *) exit 90 ;; esac\n' > "$F/tools/gh"
chmod +x "$F/tools/gh"
cp "$ROOT/install.sh" "$FIXTURE_DISTRIBUTION/install.sh"
rm -f "$F/release/checksums.txt"
run "$FIXTURE_DISTRIBUTION/install.sh"
eq "$status" 1 'missing public release exit'
{ printf 'downloading release %s from https://github.com/fixture/mirror/releases/download/%s ...\n' "$version" "$version"
  platform_line; } > "$F/expected-out"
expected_error 'checksums.txt download failed'
output_is; preserved; passed=$((passed + 1))
unset GENTLE_CC_OWNER_REPO
# Windows names are shared by staging/publication/rollback, not just downloads.
for install_mode in release source; do
  fixture
  printf '#!/usr/bin/env bash\ncase "$1" in -s) echo MINGW64_NT ;; -m) echo x86_64 ;; esac\n' > "$F/tools/uname"
  win_asset="gentle-ai-cc_${version}_windows_amd64.exe"
  win_wrapper="gentle-cc_${version}_windows_amd64.exe"
  cp "$F/new-binary" "$F/release/$win_asset"
  cp "$F/new-wrapper" "$F/release/$win_wrapper"
  printf '%s  %s\n%s  %s\n' "$(hash "$F/new-binary")" "$win_asset" "$(hash "$F/new-wrapper")" "$win_wrapper" > "$F/release/checksums.txt"
  if [ "$install_mode" = release ]; then release --sha-only; else source_install --sha-only; fi
  eq "$status" 0 'Windows pair exit'
  bytes "$GENTLE_CC_DEST/gentle-ai-cc.exe" "$F/new-binary"
  bytes "$GENTLE_CC_DEST/gentle-cc.exe" "$F/new-wrapper"
  bytes "$GENTLE_CC_DEST/gentle-ai-cc" "$F/old-binary"
  bytes "$GENTLE_CC_DEST/gentle-cc" "$F/old-wrapper"
  eq "$(< "$F/stderr")" '' 'Windows stderr'; empty_stage
  os=windows; asset="$win_asset"; wrapper_asset="$win_wrapper"
  if [ "$install_mode" = release ]; then release_prefix > "$F/expected-out"
  else { source_prefix; printf 'built SHA256: %s\n' "$(hash "$F/new-binary")"; } > "$F/expected-out"; fi
  printf 'installed: %s/gentle-ai-cc.exe\n' "$GENTLE_CC_DEST" >> "$F/expected-out"
  : > "$F/expected-err"; output_is
  snapshot > "$F/before"
  publication_faults; export FAIL_KIND=rename FAIL_AT=2
  if [ "$install_mode" = release ]; then release --sha-only; release_prefix > "$F/expected-out"
  else source_install --sha-only; source_prefix > "$F/expected-out"; fi
  eq "$status" 1 'Windows second rename failure'
  expected_error 'cannot replace gentle-cc.exe'; output_is; preserved
  os=linux; asset="gentle-ai-cc_${version}_linux_amd64"; wrapper_asset="gentle-cc_${version}_linux_amd64"
  passed=$((passed + 1))
done

# Default release version and explicit overrides both build all twelve assets.
# Six native wrapper artifacts are built in the distribution, never the companion.
for build_version in "$version" dev-native; do
fixture
cp "$ROOT/gentle-cc-release.sh" "$FIXTURE_DISTRIBUTION/"
version_args=(); [ "$build_version" = "$version" ] || version_args=(--version "$build_version")
run "$FIXTURE_DISTRIBUTION/gentle-cc-release.sh" --repo "$FIXTURE_SOURCE" "${version_args[@]}" --out "$F/out"
eq "$status" 0 'release build exit'
eq "$(< "$F/stderr")" '' 'release build stderr'
for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64; do
  suffix=''; [ "${target%/*}" != windows ] || suffix=.exe
  for product in gentle-ai-cc gentle-cc; do
    name="${product}_${build_version}_${target%/*}_${target#*/}${suffix}"
    [ -f "$F/out/$name" ] || fail "missing release artifact $name"
    if [ "$product" = gentle-cc ]; then bytes "$F/out/$name" "$F/new-wrapper"
    else bytes "$F/out/$name" "$F/new-binary"; fi
    grep -Fx "$(hash "$F/out/$name")  $name" "$F/out/checksums.txt" >/dev/null || fail "missing checksum $name"
  done
done
eq "$(wc -l < "$F/out/checksums.txt" | tr -d ' ')" 12 'manifest count'
[ ! -e "$F/out/gentle-cc" ] || fail 'obsolete universal wrapper published'
run "$FIXTURE_DISTRIBUTION/gentle-cc-release.sh" --wrapper "$F/new-wrapper"
eq "$status" 2 'obsolete override exit'
eq "$(< "$F/stdout")" '' 'obsolete override stdout'
eq "$(< "$F/stderr")" 'release: --wrapper is obsolete; native wrappers are built from this distribution module for each target' 'obsolete override stderr'
passed=$((passed + 1))
done
printf 'GREEN: %s Bash installer cases passed; POSIX mode support: %s.\n' "$passed" "$MODES"
