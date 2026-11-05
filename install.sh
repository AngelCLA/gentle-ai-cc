#!/usr/bin/env bash
# install.sh — installer for the Command Code companion of gentle-ai.
#
# Private repository note: anonymous curl / public release downloads do not work
# against a private repo. This script therefore prefers, in order:
#
#   1. an explicit source override (GENTLE_CC_SOURCE / GENTLE_CC_REF)
#   2. local ./dist/checksums.txt (artifacts from gentle-cc-release.sh)
#   3. an authenticated download of the release via `gh`
# There is no automatic source fallback if release selection/download fails.
#
# Environment:
#   GENTLE_CC_VERSION   release tag/prefix (default 4.3.1-cc.1)
#   GENTLE_CC_DEST      install dir        (default ~/.local/bin)
#   GENTLE_CC_SOURCE    git URL to build from instead of a release
#   GENTLE_CC_REF       commit/tag for GENTLE_CC_SOURCE
#   GENTLE_CC_OWNER_REPO owner/repo        (default AngelCLA/gentle-ai-cc)
set -euo pipefail

VERSION="${GENTLE_CC_VERSION:-4.3.1-cc.1}"
OWNER_REPO="${GENTLE_CC_OWNER_REPO:-AngelCLA/gentle-ai-cc}"
here="$(cd "$(dirname "$0")" && pwd)"

# 1. Build from source when explicitly requested.
if [ -n "${GENTLE_CC_SOURCE:-}" ]; then
  exec "$here/gentle-cc-install.sh" --from-source "$GENTLE_CC_SOURCE" \
    ${GENTLE_CC_REF:+--ref "$GENTLE_CC_REF"} --version "$VERSION" "$@"
fi

# 2. Local artifacts (e.g. after gentle-cc-release.sh).
if [ -f "$here/dist/checksums.txt" ]; then
  echo "using local artifacts in $here/dist"
  exec "$here/gentle-cc-install.sh" --from-release "file://$here/dist" \
    --version "$VERSION" "$@"
fi

# 3. Authenticated download of the release via gh (private repo safe).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "downloading release $VERSION from $OWNER_REPO via gh ..."
  gh release download "$VERSION" -R "$OWNER_REPO" -D "$tmp" || {
    echo "release $VERSION not found; build from source with GENTLE_CC_SOURCE=<git-url>" >&2
    exit 1
  }
  status=0
  "$here/gentle-cc-install.sh" --from-release "file://$tmp" \
    --version "$VERSION" "$@" || status=$?
  exit "$status"  # Run the parent's EXIT cleanup on child success or failure.
fi

echo "no local dist/ and no authenticated gh; set GENTLE_CC_SOURCE=<git-url> to build from source" >&2
exit 1
