#!/usr/bin/env bash
# Produces a vendored-crates archive for a Slint release, so the vcpkg port's build
# can run with cargo entirely offline. Run this once per Slint version, publish the
# resulting archive as a release asset on this registry, then fill in its URL/SHA512
# in ports/slint/portfile.cmake.
#
# Usage: scripts/vendor-crates.sh <slint-version>
set -euo pipefail

VERSION="${1:?usage: vendor-crates.sh <slint-version> (e.g. 1.17.1)}"
OUT_DIR="$(pwd)"
ARCHIVE_NAME="slint-${VERSION}-vendor.tar.zst"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Cloning slint-ui/slint at v${VERSION}..."
git clone --depth 1 --branch "v${VERSION}" https://github.com/slint-ui/slint.git "${WORKDIR}/slint"

echo "Vendoring crates.io dependencies (cargo vendor)..."
(cd "${WORKDIR}/slint" && cargo vendor --locked vendor >/dev/null)

echo "Archiving..."
tar --sort=name --owner=0 --group=0 --mtime='UTC 1970-01-01' \
    -C "${WORKDIR}/slint" \
    -I 'zstd -19 -T0' \
    -cf "${OUT_DIR}/${ARCHIVE_NAME}" vendor

SHA512="$(sha512sum "${OUT_DIR}/${ARCHIVE_NAME}" | cut -d' ' -f1)"

echo
echo "Wrote ${OUT_DIR}/${ARCHIVE_NAME}"
echo "SHA512: ${SHA512}"
echo
echo "Next steps:"
echo "  1. Publish ${ARCHIVE_NAME} as a release asset on this registry's GitHub repo"
echo "     (e.g. tag slint-v${VERSION})."
echo "  2. Update ports/slint/portfile.cmake: set VENDOR_ARCHIVE's URLS to the release"
echo "     asset URL and SHA512 to ${SHA512}."
echo "  3. Re-run 'vcpkg x-add-version' if the portfile change should be part of a new"
echo "     port-version."
