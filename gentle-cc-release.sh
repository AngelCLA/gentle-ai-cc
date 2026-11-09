#!/usr/bin/env bash
# gentle-cc-release.sh — build reproducible, per-platform Command Code companion
# artifacts plus the wrapper and a checksum manifest, ready to attach to a release.
#
# Usage:
#   gentle-cc-release.sh [--repo DIR] [--version V] [--out DIR]
#
# Reproducibility: -trimpath and -buildvcs=false make the binary independent of
# the build directory and VCS state. The version string is injected from --version
# so two runs of the same commit produce byte-identical binaries.
#
# Produces in --out:
#   gentle-ai-cc_<V>_<os>_<arch>[.exe]   companion binaries (6 platforms)
#   gentle-cc_<V>_<os>_<arch>[.exe]      native wrappers (6 platforms)
# --wrapper PATH is obsolete: no universal Bash wrapper override is accepted.
# 4.3.1-cc.4 is the current native release; 4.3.1-cc.1 is the legacy wrapper.
# The companion module is built from --repo; when that ref did not change, the
# previously verified companion assets may be republished under the new version.
#   checksums.txt                        sha256 of every artifact above
set -euo pipefail

REPO="${GENTLE_CC_REPO:-$HOME/dev/gentle-ai}"
VERSION="4.3.1-cc.4"
OUT="$(pwd)/dist"
DISTRIBUTION="$(cd "$(dirname "$0")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --wrapper) echo "release: --wrapper is obsolete; native wrappers are built from this distribution module for each target" >&2; exit 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$REPO" ] || { echo "repo not found: $REPO" >&2; exit 1; }
command -v go >/dev/null 2>&1 || { echo "go required" >&2; exit 1; }
[ -f "$DISTRIBUTION/go.mod" ] || { echo "wrapper module not found: $DISTRIBUTION/go.mod" >&2; exit 1; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
: > "$OUT/checksums.txt"

# Portable sha256 (Linux: sha256sum, macOS/BSD: shasum).
sha256_of() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$1" | awk '{print $1}'
}
# Emit "hash  name" lines compatible with the installer's parser.
manifest_line() {
  local dir="$1" name="$2"
  printf '%s  %s\n' "$(sha256_of "$dir/$name")" "$name"
}

targets="linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64"

for t in $targets; do
  os="${t%/*}"; arch="${t#*/}"
  bin="gentle-ai-cc_${VERSION}_${os}_${arch}"
  [ "$os" = "windows" ] && bin="${bin}.exe"
  echo "building ${os}/${arch} ..."
  ( cd "$REPO" && \
    GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
    go build -trimpath -buildvcs=false \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o "$OUT/$bin" ./cmd/gentle-ai )
  manifest_line "$OUT" "$bin" >> "$OUT/checksums.txt"
  wrapper="gentle-cc_${VERSION}_${os}_${arch}"
  [ "$os" != windows ] || wrapper="${wrapper}.exe"
  ( cd "$DISTRIBUTION" && \
    GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
    go build -trimpath -buildvcs=false \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o "$OUT/$wrapper" ./cmd/gentle-cc )
  manifest_line "$OUT" "$wrapper" >> "$OUT/checksums.txt"
done

echo
echo "artifacts in $OUT:"
ls -1 "$OUT"
echo
echo "manifest: $OUT/checksums.txt"
echo
echo "publish: gh release create ${VERSION} \"$OUT\"/* --title \"${VERSION}\" --notes \"Command Code companion ${VERSION}\""
