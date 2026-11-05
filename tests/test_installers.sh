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
    if [ "${1:-both}" = both ]; then printf '%s  gentle-cc\n' "$(hash "$F/new-wrapper")"; fi
  } > "$F/release/checksums.txt"
}
fixture() {
  F="$(mktemp -d "$SUITE/case.XXXXXXXX")"
  export HOME="$F/home" TMPDIR="$F/tmp" GENTLE_CC_DEST="$F/bin"
  export TOOL_LOG="$F/tool-log" TRANSPORT_LOG="$F/transport-log"
  export FIXTURE_SOURCE="$F/external module with spaces"
  export FIXTURE_DISTRIBUTION="$F/distribution with spaces"
  export FAIL_COUNT="$F/failure-count" FAIL_KIND='' FAIL_AT=0 FAIL_RESTORE=0 CHANGE_DISTRIBUTION=0
  mkdir -p "$HOME" "$TMPDIR" "$GENTLE_CC_DEST" "$F/release" "$F/tools" "$FIXTURE_SOURCE" "$FIXTURE_DISTRIBUTION"
  cp "$ROOT/gentle-cc-install.sh" "$FIXTURE_DISTRIBUTION/"
  cp "$ROOT/gentle-cc" "$FIXTURE_DISTRIBUTION/gentle-cc"
  printf 'new binary\n' > "$F/new-binary"
  printf 'new wrapper\n' > "$F/new-wrapper"
  cp "$F/new-binary" "$F/release/$asset"
  cp "$F/new-wrapper" "$F/release/gentle-cc"
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
case "$2" in file://*) source=${2#file://} ;; *) exit 91 ;; esac
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
printf 'go %s\n' "$1" >> "$TOOL_LOG"
[ "$1" = build ] || exit 91
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then printf 'new binary\n' > "$2"; exit 0; fi
  shift
done
exit 92
TOOL
  chmod +x "$F/tools/"*
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
    printf 'downloading gentle-cc wrapper ...\nchecksum OK (gentle-cc): %s\n' "$(hash "$F/new-wrapper")"
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

os="$(uname -s | tr 'A-Z' 'a-z')"
case "$os" in mingw*|msys*|cygwin*) os=windows; ext=.exe ;; linux|darwin) ext='' ;; *) fail "unsupported host: $os" ;; esac
case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) fail 'unsupported architecture' ;; esac
asset="gentle-ai-cc_4.3.1-cc.1_${os}_${arch}${ext}"
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
mutant=${mutant/'cp "$source_wrapper" "$tmp/gentle-cc"'/'printf "wrong wrapper\n" > "$tmp/gentle-cc"'}
printf '%s\n' "$mutant" > "$FIXTURE_DISTRIBUTION/gentle-cc-install.sh"
source_install
red_status=0
(bytes "$GENTLE_CC_DEST/gentle-cc" "$ROOT/gentle-cc") > "$F/red-log" 2>&1 || red_status=$?
eq "$red_status" 1 'deliberate mutant detection exit'
printf 'RED: isolated wrong-wrapper installer exit=%s; assertion exit=%s; %s\n' "$status" "$red_status" "$(< "$F/red-log")"

# test_validation_failures_preserve_both_destinations
for failure in wrapper-mismatch wrapper-missing wrapper-entry binary-mismatch binary-entry; do
  fixture
  release_prefix > "$F/expected-out"
  case "$failure" in
    wrapper-mismatch)
      printf tampered > "$F/release/gentle-cc"
      expected_error "checksum mismatch for gentle-cc: expected $(hash "$F/new-wrapper") got $(hash "$F/release/gentle-cc")"
      # The verification line for the wrapper must not have been printed.
      { platform_line; printf 'downloading %s ...\nchecksum OK (%s): %s\ndownloading gentle-cc wrapper ...\n' "$asset" "$asset" "$(hash "$F/new-binary")"; } > "$F/expected-out" ;;
    wrapper-missing|wrapper-entry)
      if [ "$failure" = wrapper-missing ]; then
        mv "$F/release/gentle-cc" "$F/removed-wrapper"
        expected_error 'wrapper download failed'
      else manifest binary; expected_error 'no checksum entry for gentle-cc'; fi
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
    mv "$F/release/gentle-cc" "$F/removed-wrapper"; manifest binary
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
  { printf 'checksums.txt\n%s\n' "$asset"; [ "$requested" != both ] || printf 'gentle-cc\n'; } > "$F/expected-transport"
  bytes "$TRANSPORT_LOG" "$F/expected-transport"; empty_stage
  passed=$((passed + 1))
done

# Source wrapper provenance, early staging, and absent external wrapper.
for external in present absent; do
  fixture
  cp "$FIXTURE_DISTRIBUTION/gentle-cc" "$F/expected-wrapper"
  if [ "$external" = present ]; then
    printf 'unrelated external wrapper\n' > "$FIXTURE_SOURCE/gentle-cc"
    export CHANGE_DISTRIBUTION=1
  else mv "$GENTLE_CC_DEST/gentle-cc" "$F/removed-wrapper"; fi
  source_install; check_source_success
  bytes "$GENTLE_CC_DEST/gentle-cc" "$F/expected-wrapper"; executable "$GENTLE_CC_DEST/gentle-cc"
  printf 'git clone\ngit checkout\ngo build\n' > "$F/expected-tools"; bytes "$TOOL_LOG" "$F/expected-tools"
  passed=$((passed + 1))
done
for existing in yes no; do
  fixture
  mv "$FIXTURE_DISTRIBUTION/gentle-cc" "$F/removed-distribution-wrapper"
  printf 'external wrapper\n' > "$FIXTURE_SOURCE/gentle-cc"
  if [ "$existing" = no ]; then export GENTLE_CC_DEST="$F/not created destination"; fi
  source_install; eq "$status" 1 'missing source wrapper exit'
  : > "$F/expected-out"; expected_error "source wrapper unavailable: $FIXTURE_DISTRIBUTION/gentle-cc"; output_is
  if [ "$existing" = yes ]; then preserved; else [ ! -e "$GENTLE_CC_DEST" ] || fail 'destination created'; fi
  [ ! -e "$TOOL_LOG" ] || fail 'tools ran before wrapper preflight'; empty_stage
  passed=$((passed + 1))
done
for existing in yes no; do
  fixture
  mv "$FIXTURE_DISTRIBUTION/gentle-cc" "$F/removed-distribution-wrapper"
  printf 'external wrapper\n' > "$FIXTURE_SOURCE/gentle-cc"
  if [ "$existing" = no ]; then mv "$GENTLE_CC_DEST/gentle-cc" "$F/removed-wrapper"; fi
  source_install --no-wrapper --sha-only; check_source_success quiet
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
  printf 'downloading release 4.3.1-cc.1 from fixture/repo via gh ...\nchild stdout\n' > "$F/expected-out"
  printf 'child stderr\n' > "$F/expected-err"
  output_is; preserved; passed=$((passed + 1))
done
printf 'GREEN: %s Bash installer cases passed; POSIX mode support: %s.\n' "$passed" "$MODES"
