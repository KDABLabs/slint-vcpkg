#!/usr/bin/env bash
# Bumps ports/slint to a new Slint release and regenerates the versions/ database.
#
# Prerequisites:
#   - A vcpkg binary on PATH, or set VCPKG=/path/to/vcpkg (any vcpkg checkout works --
#     it's used purely as a generic tool here, not tied to this registry).
#   - Run scripts/vendor-crates.sh <version> FIRST, publish the resulting archive as a
#     release asset, and pass its URL with --vendor-url.
#
# Usage: scripts/add-version.sh <version> --vendor-url URL --vendor-sha512 SHA512
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG="${VCPKG:-$(command -v vcpkg || true)}"

VERSION=""
VENDOR_URL=""
VENDOR_SHA512=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vendor-url) VENDOR_URL="$2"; shift 2 ;;
        --vendor-sha512) VENDOR_SHA512="$2"; shift 2 ;;
        *)
            if [[ -z "${VERSION}" ]]; then VERSION="$1"; shift; else
                echo "Unexpected argument: $1" >&2; exit 1
            fi
            ;;
    esac
done

if [[ -z "${VERSION}" || -z "${VENDOR_URL}" || -z "${VENDOR_SHA512}" ]]; then
    echo "usage: add-version.sh <slint-version> --vendor-url URL --vendor-sha512 SHA512" >&2
    echo "  (run scripts/vendor-crates.sh <version> first to produce those two values)" >&2
    exit 1
fi
if [[ -z "${VCPKG}" ]]; then
    echo "error: no vcpkg binary found. Set VCPKG=/path/to/vcpkg or add one to PATH." >&2
    exit 1
fi

PORT_DIR="${REPO_ROOT}/ports/slint"

echo "Fetching source archive to compute its SHA512..."
SRC_SHA512="$(curl -sL "https://github.com/slint-ui/slint/archive/v${VERSION}.tar.gz" | sha512sum | cut -d' ' -f1)"

echo "Updating ${PORT_DIR}/vcpkg.json..."
jq --arg v "${VERSION}" '."version-semver" = $v | ."port-version" = 0' \
    "${PORT_DIR}/vcpkg.json" > "${PORT_DIR}/vcpkg.json.tmp"
mv "${PORT_DIR}/vcpkg.json.tmp" "${PORT_DIR}/vcpkg.json"

echo "Updating ${PORT_DIR}/portfile.cmake..."
python3 - "${PORT_DIR}/portfile.cmake" "${SRC_SHA512}" "${VENDOR_URL}" "${VENDOR_SHA512}" <<'PYEOF'
import re, sys
path, src_sha512, vendor_url, vendor_sha512 = sys.argv[1:5]
text = open(path).read()
text = re.sub(
    r'(REPO slint-ui/slint\s+REF "v\$\{VERSION\}"\s+SHA512 )[0-9a-fA-F]+',
    r'\g<1>' + src_sha512, text, count=1)
text = re.sub(r'(URLS ")[^"]+(")', r'\g<1>' + vendor_url + r'\g<2>', text, count=1)
text = re.sub(
    r'(FILENAME "slint-\$\{VERSION\}-vendor\.tar\.zst"\s+SHA512 )[0-9a-fA-F]+',
    r'\g<1>' + vendor_sha512, text, count=1)
open(path, 'w').write(text)
PYEOF

echo "Regenerating versions/ database..."
"${VCPKG}" x-add-version \
    --x-builtin-ports-root="${REPO_ROOT}/ports" \
    --x-builtin-registry-versions-dir="${REPO_ROOT}/versions" \
    --overwrite-version \
    slint

echo
echo "Done. Review the diff, then commit ports/slint and versions/."
