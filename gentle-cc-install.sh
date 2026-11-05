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
#       companion reproducibly. Requires Go 1.25+.
#
# Both modes install:
#   ~/.local/bin/gentle-ai-cc     (companion binary)
#   ~/.local/bin/gentle-cc        (wrapper, unless --no-wrapper)
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
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
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

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

install_release() {
  command -v curl >/dev/null 2>&1 || die "curl required for --from-release"
  base="${SRC%/}"
  curl -fsSL "$base/checksums.txt" -o "$tmp/checksums.txt" || die "checksums.txt download failed"
  echo "downloading $asset ..."
  curl -fsSL "$base/$asset" -o "$tmp/$asset" || die "download failed: $base/$asset"
  verify_against "$tmp/$asset" "$asset" "$tmp/checksums.txt"
  cp "$tmp/$asset" "$DEST_DIR/$BIN_NAME"
  chmod +x "$DEST_DIR/$BIN_NAME"

  if [ "$NO_WRAPPER" = "0" ]; then
    echo "downloading gentle-cc wrapper ..."
    curl -fsSL "$base/gentle-cc" -o "$tmp/gentle-cc" || die "wrapper download failed"
    verify_against "$tmp/gentle-cc" "gentle-cc" "$tmp/checksums.txt"
    cp "$tmp/gentle-cc" "$WRAPPER"
    chmod +x "$WRAPPER"
  fi
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
  cp "$tmp/$BIN_NAME$ext" "$DEST_DIR/$BIN_NAME"
  chmod +x "$DEST_DIR/$BIN_NAME"
  echo "built SHA256: $(sha256_of "$DEST_DIR/$BIN_NAME")"

  if [ "$NO_WRAPPER" = "0" ] && [ -f "$tmp/src/gentle-cc" ]; then
    cp "$tmp/src/gentle-cc" "$WRAPPER"; chmod +x "$WRAPPER"
  fi
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
