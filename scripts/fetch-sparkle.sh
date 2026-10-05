#!/bin/bash
# Puts Sparkle, the updater, at .build/vendor/Sparkle-<version>/ once, checked
# against a pinned SHA-256, and prints that folder. The archive is never
# committed: .build/ is ignored, and a fresh checkout fetches the same bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="2.10.0"
SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
VENDOR="${ROOT}/.build/vendor"
DEST="${VENDOR}/Sparkle-${VERSION}"

# The binary itself, not just the folder: an unpack cut short left a folder
# this used to accept, and the build then failed with "no such module".
if [ -f "${DEST}/Sparkle.framework/Versions/B/Sparkle" ]; then
  echo "${DEST}"
  exit 0
fi

mkdir -p "${VENDOR}"
# One fetch at a time: two first builds at once each saw the other's
# half-written archive fail its checksum.
LOCK="${VENDOR}/.sparkle-fetch.lock"
for _ in $(seq 1 600); do mkdir "${LOCK}" 2>/dev/null && break; sleep 0.2; done
trap 'rmdir "${LOCK}" 2>/dev/null || true' EXIT
if [ -f "${DEST}/Sparkle.framework/Versions/B/Sparkle" ]; then
  echo "${DEST}"
  exit 0
fi

ARCHIVE="${VENDOR}/Sparkle-${VERSION}.tar.xz"
if [ ! -f "${ARCHIVE}" ]; then
  echo "Fetching Sparkle ${VERSION}…" >&2
  curl -fsSL -o "${ARCHIVE}.part" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
  mv "${ARCHIVE}.part" "${ARCHIVE}"
fi
if ! echo "${SHA256}  ${ARCHIVE}" | shasum -a 256 -c - >/dev/null 2>&1; then
  rm -f "${ARCHIVE}"
  echo "error: Sparkle ${VERSION} did not match its pinned checksum; nothing was unpacked" >&2
  exit 1
fi
# Unpacked beside and moved into place whole.
UNPACK="$(mktemp -d "${VENDOR}/.unpack.XXXXXX")"
tar -xJf "${ARCHIVE}" -C "${UNPACK}"
rm -rf "${DEST}"
mv "${UNPACK}" "${DEST}"
echo "${DEST}"
