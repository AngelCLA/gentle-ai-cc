#!/usr/bin/env bash
# install.sh — one-line installer for the Command Code companion of gentle-ai.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
#
# Optional environment:
#   GENTLE_CC_VERSION   release tag/prefix (default 4.3.1-cc.1)
#   GENTLE_CC_DEST      install dir        (default ~/.local/bin)
#   GENTLE_AI_SOURCE    git URL to build from instead of a release
#   GENTLE_AI_REF       commit/tag for GENTLE_AI_SOURCE
set -euo pipefail

VERSION="${GENTLE_CC_VERSION:-4.3.1-cc.1}"
OWNER_REPO="${GENTLE_CC_OWNER_REPO:-<owner>/<repo>}"
BASE="https://github.com/${OWNER_REPO}/releases/download/${VERSION}"

here="$(dirname "$0")"
if [ -f "$here/gentle-cc-install.sh" ]; then
  # running from a checkout: use the bundled installer directly
  exec "$here/gentle-cc-install.sh" --from-release "$BASE" "$@"
fi

# running from curl: fetch the installer, then run it
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/${OWNER_REPO}/main/gentle-cc-install.sh" -o "$tmp"
bash "$tmp" --from-release "$BASE" "$@"
