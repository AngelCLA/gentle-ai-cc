#!/usr/bin/env bash
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
#       4.3.1-cc.2 is the native release; 4.3.1-cc.1 is the legacy wrapper.
#
# Options:
#   --ref REF       Source commit/tag (default the pinned commit).
#   --version V     Release asset version / source build version (default 4.3.1-cc.2).
#   --no-wrapper    Install only the binary; leave any existing wrapper unchanged.
#   --sha-only      Still installs; suppresses final next-step guidance only.
# GENTLE_CC_DEST overrides the default destination below; it does not update PATH.
#
# Both modes install:
#   ~/.local/bin/gentle-ai-cc     (companion binary; .exe on Windows)
#   ~/.local/bin/gentle-cc        (native wrapper; .exe on Windows, unless --no-wrapper)
# Controlled publication errors restore this invocation's changed files only.
# Not an atomic pair or crash/signal-safe; see README for recovery limitations.
set -euo pipefail

DEST_DIR="${GENTLE_CC_DEST:-$HOME/.local/bin}"
BIN_NAME="gentle-ai-cc"
WRAPPER_NAME="gentle-cc"
PINNED_REF="768e6b213c795f574ee837e3a6ce9b4274ee6280"
VERSION="4.3.1-cc.2"

MODE=""; SRC=""; REF="$PINNED_REF"; NO_WRAPPER=0; SHA_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --from-release) MODE="release"; SRC="$2"; shift 2 ;;
    --from-source)  MODE="source";  SRC="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --sha-only) SHA_ONLY=1; shift ;;
    --no-wrapper) NO_WRAPPER=1; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
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
BIN_NAME="gentle-ai-cc$ext"
WRAPPER_NAME="gentle-cc$ext"
WRAPPER="$DEST_DIR/$WRAPPER_NAME"
asset="gentle-ai-cc_${VERSION}_${os}_${arch}${ext}"
wrapper_asset="gentle-cc_${VERSION}_${os}_${arch}${ext}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$MODE" = "source" ] && [ "$NO_WRAPPER" = "0" ]; then
  # Resolve this module before clone/build; never use the external companion.
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$script_dir/go.mod" ] && [ -r "$script_dir/go.mod" ] || \
    die "source wrapper unavailable: $script_dir/go.mod"
fi

echo "platform: ${os}/${arch}  asset: ${asset}"

sha256_of() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$1" | awk '{print $1}'
}

verify_against() {
  local file="$1" name="$2" manifest="$3"
  local expected actual
  # Match filenames literally: release versions may contain regex operators.
  expected="$(awk -v name="$name" '
    {
      sub(/\r$/, "")
      filename = $2
      sub(/^\*/, "", filename)
      if (filename == name) print $1
    }
  ' "$manifest")" || die "cannot read checksum manifest for $name"
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
  [ "$NO_WRAPPER" = 1 ] || names+=("$WRAPPER_NAME")
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
    [ "$name" != "$WRAPPER_NAME" ] || input="$tmp/$WRAPPER_NAME"
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
    curl -fsSL "$base/$wrapper_asset" -o "$tmp/$WRAPPER_NAME" || die "wrapper download failed"
    verify_against "$tmp/$WRAPPER_NAME" "$wrapper_asset" "$tmp/checksums.txt"
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
  if [ "$NO_WRAPPER" = 0 ]; then
    ( cd "$script_dir" && GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
      go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.version=${VERSION}" \
        -o "$tmp/$WRAPPER_NAME" ./cmd/gentle-cc ) || die "wrapper build failed"
  fi
  ( cd "$tmp/src" && GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
      go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.version=${VERSION}" \
        -o "$tmp/$BIN_NAME" ./cmd/gentle-ai ) || die "build failed"
  publish_artifacts "$tmp/$BIN_NAME"
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
