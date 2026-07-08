#!/usr/bin/env bash
# Rebuild + publish the Turnip driver catalogue to aanze/rocknix-turnip.
#
# Usage:
#   publish-turnip-catalog.sh                 # rebuild ALL sources in catalog-sources.txt
#   publish-turnip-catalog.sh stable:26.2.0   # add that source (if new), then rebuild all
#   publish-turnip-catalog.sh git:origin/main:nightly --no-publish   # build only, don't upload
#
# Non-flag args are appended to catalog-sources.txt (deduped); flags are
# forwarded to build-turnip-catalog.sh. Driven 1-click from Windows by
# turnip-catalog.bat (which just calls this through WSL).
set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/marc/src/rocknix}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES="${SOURCES:-$SCRIPT_DIR/catalog-sources.txt}"
CI="${REPO_DIR}/projects/ROCKNIX/packages/tools/gpu-driver/ci/build-turnip-catalog.sh"
RELEASE_REPO="${RELEASE_REPO:-aanze/rocknix-turnip}"
TAG="${TAG:-catalog}"

[ -f "$CI" ] || { echo "CI script missing: $CI" >&2; exit 1; }
[ -f "$SOURCES" ] || { echo "sources file missing: $SOURCES" >&2; exit 1; }

forward=()
for arg in "$@"; do
  case "$arg" in
    -*) forward+=("$arg") ;;                       # flag -> forward to the CI script
    *)                                             # spec -> add to the sources list
      if grep -qxF "$arg" "$SOURCES" 2>/dev/null; then
        echo "already in catalogue: $arg"
      else
        printf '%s\n' "$arg" >> "$SOURCES"
        echo "added source: $arg"
      fi
      ;;
  esac
done

echo "=== catalogue sources ==="
sed 's/#.*//' "$SOURCES" | awk 'NF{print "  - "$0}'

cd "$REPO_DIR"
exec env PROJECT=ROCKNIX DEVICE=SM8750 ARCH=aarch64 \
  "$CI" --repo "$RELEASE_REPO" --tag "$TAG" --sources "$SOURCES" "${forward[@]}"
