#!/usr/bin/env bash
# gentle-cc-install.sh — reproducible, verifiable installer for the Command Code
# companion of gentle-ai.
#
# Two modes:
#
#   --from-release URL_PREFIX
#       Download the prebuilt binary for this OS/arch and the wrapper from
#       URL_PREFIX, and verify both against checksums.txt in the same prefix.
#       No Go required.
#       Example: --from-release https://github.com/<you>/gentle-ai-cc/releases/download/4.3.1-cc.1
#
#   --from-source GIT_URL [--ref REF]
#       Clone/checkout GIT_URL at REF (default the pinned commit) and build the
#       companion reproducibly. Requires Go 1.25+. The wrapper is staged from
#       beside this installer before changing the destination, not from GIT_URL.
#       A missing wrapper is an error unless --no-wrapper is given.
#
# Both modes install:
#   ~/.local/bin/gentle-ai-cc     (companion binary)
#   ~/.local/bin/gentle-cc        (wrapper, unless --no-wrapper)
# Controlled publication errors restore this invocation's changed files only.
# Not an atomic pair or crash/signal-safe; see README for recovery limitations.
set -euo pipefail

DEST_DIR="${GENTLE_CC_DEST:-$HOME/.local/bin}"
BIN_NAME="gentle-ai-cc"
WRAPPER="$DEST_DIR/gentle-cc"
PINNED_REF="768e6b213c795f574ee837e3a6ce9b4274ee6280"
VERSION="4.3.1-cc.1"

MODE=""; SRC=""; REF="$PINNED_REF"; NO_WRAPPER=0; SHA_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --from-release) MODE="release"; SRC="$2"; shift 2 ;;
    --from-source)  MODE="source";  SRC="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --sha-only) SHA_ONLY=1; shift ;;
    --no-wrapper) NO_WRAPPER=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
os="$(uname -s | tr 'A-Z' 'a-z')"
case "$os" in
  linux|darwin) ;;
  mingw*|msys*|cygwin*) os="windows" ;;
  *) die "unsupported OS: $os" ;;
esac
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) die "unsupported arch: $arch" ;;
esac

ext=""; [ "$os" = "windows" ] && ext=".exe"
asset="gentle-ai-cc_${VERSION}_${os}_${arch}${ext}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$MODE" = "source" ] && [ "$NO_WRAPPER" = "0" ]; then
  # Resolve relative to this distribution, never the caller's working directory
  # or the external module. Stage before clone/build or any destination changes.
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  source_wrapper="$script_dir/gentle-cc"
  [ -f "$source_wrapper" ] && [ -r "$source_wrapper" ] || \
    die "source wrapper unavailable: $source_wrapper"
  cp "$source_wrapper" "$tmp/gentle-cc" || die "cannot stage source wrapper: $source_wrapper"
fi

echo "platform: ${os}/${arch}  asset: ${asset}"

sha256_of() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$1" | awk '{print $1}'
}

verify_against() {
  local file="$1" name="$2" manifest="$3"
  local expected actual
  expected="$(grep -E "[[:space:]]\*?${name}\$" "$manifest" | awk '{print $1}')"
  [ -n "$expected" ] || die "no checksum entry for $name"
  actual="$(sha256_of "$file")"
  [ "$expected" = "$actual" ] || die "checksum mismatch for $name: expected $expected got $actual"
  echo "checksum OK ($name): $actual"
}

# Only regular requested paths are supported. Do not follow destination links
# or let mv interpret a directory as a container. Requires exclusive destination
# access: portable shell preflight cannot defend against concurrent path swaps.
safe_destination() {
  [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -f "$1" ]; }
}

publication_abort() {
  local message="$1" name failed=0 restore_failed
  # changed[] is populated only after successful renames, never for unrequested
  # paths. Backups are outside the ordinary download-staging EXIT cleanup.
  # The + expansion also supports empty arrays under older Bash nounset.
  for name in "${changed[@]+"${changed[@]}"}"; do
    restore_failed=0
    if ! safe_destination "$DEST_DIR/$name"; then
      restore_failed=1
    elif [ -f "$publication/old-$name" ]; then
      mv -f "$publication/old-$name" "$DEST_DIR/$name" || restore_failed=1
    else
      rm -f "$DEST_DIR/$name" || restore_failed=1
    fi
    if [ "$restore_failed" = 1 ]; then
      failed=1
      printf 'install: restoration failed for %s\n' "$DEST_DIR/$name" >&2
    fi
  done
  if [ "$failed" = 1 ]; then
    printf 'install: backups retained at %s; manual recovery required\n' "$publication" >&2
  else
    rm -rf "$publication" || \
      printf 'install: cannot remove publication staging: %s\n' "$publication" >&2
  fi
  die "$message"
}

publish_artifacts() {
  local binary="$1" name input publication
  local names=("$BIN_NAME") changed=()
  [ "$NO_WRAPPER" = 1 ] || names+=("gentle-cc")
  for name in "${names[@]}"; do
    safe_destination "$DEST_DIR/$name" || die "unsafe destination: $DEST_DIR/$name"
  done
  [ ! -L "$DEST_DIR" ] && { [ ! -e "$DEST_DIR" ] || [ -d "$DEST_DIR" ]; } || \
    die "unsafe destination directory: $DEST_DIR"
  mkdir -p "$DEST_DIR" || die "cannot create destination: $DEST_DIR"
  publication="$(mktemp -d "$DEST_DIR/.gentle-cc-install.XXXXXXXX")" || \
    die "cannot create publication staging"

  # Stage and set permissions before touching installed files. Snapshot every
  # requested old file (including its mode) before the first replacement.
  for name in "${names[@]}"; do
    input="$binary"
    [ "$name" != gentle-cc ] || input="$tmp/gentle-cc"
    cp "$input" "$publication/new-$name" || publication_abort "cannot stage $name"
    chmod +x "$publication/new-$name" || publication_abort "cannot set permissions for $name"
    if [ -e "$DEST_DIR/$name" ]; then
      cp -p "$DEST_DIR/$name" "$publication/old-$name" || publication_abort "cannot snapshot $name"
    fi
  done
  for name in "${names[@]}"; do
    safe_destination "$DEST_DIR/$name" || publication_abort "unsafe destination: $DEST_DIR/$name"
    mv -f "$publication/new-$name" "$DEST_DIR/$name" || publication_abort "cannot replace $name"
    changed+=("$name")
  done
  rm -rf "$publication" || die "cannot remove publication staging: $publication"
}

install_release() {
  command -v curl >/dev/null 2>&1 || die "curl required for --from-release"
  base="${SRC%/}"
  curl -fsSL "$base/checksums.txt" -o "$tmp/checksums.txt" || die "checksums.txt download failed"
  echo "downloading $asset ..."
  curl -fsSL "$base/$asset" -o "$tmp/$asset" || die "download failed: $base/$asset"
  verify_against "$tmp/$asset" "$asset" "$tmp/checksums.txt"

  if [ "$NO_WRAPPER" = "0" ]; then
    echo "downloading gentle-cc wrapper ..."
    curl -fsSL "$base/gentle-cc" -o "$tmp/gentle-cc" || die "wrapper download failed"
    verify_against "$tmp/gentle-cc" "gentle-cc" "$tmp/checksums.txt"
  fi

  # Verify every requested artifact before publication starts.
  publish_artifacts "$tmp/$asset"
}

install_source() {
  command -v go >/dev/null 2>&1 || die "go required for --from-source"
  command -v git >/dev/null 2>&1 || die "git required for --from-source"
  echo "cloning $SRC ..."
  git clone --quiet "$SRC" "$tmp/src" || die "clone failed"
  ( cd "$tmp/src" && git checkout --quiet "$REF" ) || die "checkout $REF failed"
  echo "building at $REF (reproducible) ..."
  ( cd "$tmp/src" && GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
      go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.version=${VERSION}" \
        -o "$tmp/$BIN_NAME$ext" ./cmd/gentle-ai ) || die "build failed"
  publish_artifacts "$tmp/$BIN_NAME$ext"
  echo "built SHA256: $(sha256_of "$DEST_DIR/$BIN_NAME")"
}

case "$MODE" in
  release) install_release ;;
  source)  install_source ;;
  *) die "choose --from-release URL or --from-source GIT_URL" ;;
esac

echo "installed: $DEST_DIR/$BIN_NAME"
[ "$SHA_ONLY" = "1" ] && { exit 0; }
[ "$NO_WRAPPER" = "1" ] || [ -f "$WRAPPER" ] || \
  echo "note: wrapper not installed; place gentle-cc at $WRAPPER"

echo
echo "next:"
echo "  $DEST_DIR/$BIN_NAME version"
echo "  $WRAPPER install --preset full-gentleman   # or: $WRAPPER sync"
