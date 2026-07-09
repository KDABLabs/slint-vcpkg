#!/usr/bin/env bash
# Detects drift between Slint's own api/cpp/CMakeLists.txt SLINT_FEATURE_* options
# and the features declared in ports/slint/vcpkg.json, so new upstream features don't
# go unnoticed. Static text scan -- no cargo/rustc/cmake needed, just the CMakeLists.txt
# for the given tag.
#
# Usage: scripts/check-features.sh [slint-version]
#   Defaults to the version currently pinned in ports/slint/vcpkg.json.
#
# Exits non-zero (with a listing) if upstream has feature options this port doesn't
# expose yet, aside from the deliberate exclusions below.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_JSON="${REPO_ROOT}/ports/slint/vcpkg.json"

VERSION="${1:-$(jq -r '."version-semver"' "${VCPKG_JSON}")}"

# Deliberately not exposed as vcpkg features, with why:
#   freestanding        -- bare-metal target, out of scope for now (see README)
#   compiler             -- controls building the internal slint-compiler binary
#                            (always want it built), not a library feature
#   renderer-winit-*     -- deprecated compat aliases for the real renderer-* features,
#                            not distinct features
EXCLUDE_REGEX='^(freestanding|compiler|renderer-winit-.*)$'

CMAKELISTS_URL="https://raw.githubusercontent.com/slint-ui/slint/v${VERSION}/api/cpp/CMakeLists.txt"
echo "Fetching ${CMAKELISTS_URL}..." >&2

CMAKELISTS_FILE="$(mktemp)"
trap 'rm -f "${CMAKELISTS_FILE}"' EXIT
curl -sfL "${CMAKELISTS_URL}" -o "${CMAKELISTS_FILE}"
if [[ ! -s "${CMAKELISTS_FILE}" ]]; then
    echo "error: failed to fetch CMakeLists.txt for v${VERSION}" >&2
    exit 2
fi

upstream_features="$(python3 - "${CMAKELISTS_FILE}" <<'PYEOF'
import re, sys
text = open(sys.argv[1]).read()

names = set()

# define_cargo_feature(<name> ...) / define_cargo_dependent_feature(<name> ...)
for m in re.finditer(r'define_cargo_dependent_feature\(\s*([a-z0-9-]+)', text):
    names.add(m.group(1))
for m in re.finditer(r'define_cargo_feature\(\s*([a-z0-9-]+)', text):
    names.add(m.group(1))

# Plain option(SLINT_FEATURE_<NAME> ...) not covered by the above.
for m in re.finditer(r'option\(\s*SLINT_FEATURE_([A-Z0-9_]+)', text):
    kebab = m.group(1).lower().replace('_', '-')
    names.add(kebab)

for n in sorted(names):
    print(n)
PYEOF
)"

declared_features="$(jq -r '.features | keys[]' "${VCPKG_JSON}" | sort)"

missing=()
excluded=()
while IFS= read -r feature; do
    [[ -z "${feature}" ]] && continue
    if [[ "${feature}" =~ ${EXCLUDE_REGEX} ]]; then
        excluded+=("${feature}")
        continue
    fi
    if ! grep -qxF "${feature}" <<<"${declared_features}"; then
        missing+=("${feature}")
    fi
done <<<"${upstream_features}"

if [[ ${#excluded[@]} -gt 0 ]]; then
    echo "Deliberately excluded upstream features (unchanged): ${excluded[*]}"
fi

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "OK: no new upstream SLINT_FEATURE_* options missing from ports/slint/vcpkg.json (checked v${VERSION})."
    exit 0
fi

echo
echo "Upstream v${VERSION} has feature options not yet in ports/slint/vcpkg.json:"
for f in "${missing[@]}"; do
    echo "  - ${f}"
done
echo
echo "Add them to ports/slint/vcpkg.json's \"features\" (and the matching"
echo "vcpkg_check_features() line in portfile.cmake), or add to EXCLUDE_REGEX in this"
echo "script with a reason if they're deliberately out of scope."
exit 1
