#!/usr/bin/env bash
# gentle-cc-release.sh — build reproducible, per-platform Command Code companion
# artifacts plus the wrapper and a checksum manifest, ready to attach to a release.
#
# Usage:
#   gentle-cc-release.sh [--repo DIR] [--version V] [--out DIR] [--wrapper PATH]
#
# Reproducibility: -trimpath and -buildvcs=false make the binary independent of
# the build directory and VCS state. The version string is injected from --version
# so two runs of the same commit produce byte-identical binaries.
#
# Produces in --out:
#   gentle-ai-cc_<V>_<os>_<arch>[.exe]   companion binaries (6 platforms)
#   gentle-cc                            wrapper (platform-independent)
#   checksums.txt                        sha256 of every artifact above
set -euo pipefail

REPO="${GENTLE_CC_REPO:-$HOME/dev/gentle-ai}"
VERSION="4.3.1-cc.1"
OUT="$(pwd)/dist"
WRAPPER_SRC="$(cd "$(dirname "$0")" && pwd)/gentle-cc"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --wrapper) WRAPPER_SRC="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$REPO" ] || { echo "repo not found: $REPO" >&2; exit 1; }
command -v go >/dev/null 2>&1 || { echo "go required" >&2; exit 1; }
[ -f "$WRAPPER_SRC" ] || { echo "wrapper not found: $WRAPPER_SRC" >&2; exit 1; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
: > "$OUT/checksums.txt"

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
  ( cd "$OUT" && sha256sum "$bin" >> checksums.txt )
done

echo "copying wrapper ..."
cp "$WRAPPER_SRC" "$OUT/gentle-cc"
chmod +x "$OUT/gentle-cc"
( cd "$OUT" && sha256sum "gentle-cc" >> checksums.txt )

echo
echo "artifacts in $OUT:"
ls -1 "$OUT"
echo
echo "manifest: $OUT/checksums.txt"
echo
echo "publish: gh release create ${VERSION} \"$OUT\"/* --title \"${VERSION}\" --notes \"Command Code companion ${VERSION}\""
