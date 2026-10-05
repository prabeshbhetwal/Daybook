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

if [ -d "${DEST}/Sparkle.framework" ]; then
  echo "${DEST}"
  exit 0
fi

mkdir -p "${VENDOR}"
ARCHIVE="${VENDOR}/Sparkle-${VERSION}.tar.xz"
if [ ! -f "${ARCHIVE}" ]; then
  echo "Fetching Sparkle ${VERSION}…" >&2
  curl -fsSL -o "${ARCHIVE}" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
fi
if ! echo "${SHA256}  ${ARCHIVE}" | shasum -a 256 -c - >/dev/null 2>&1; then
  rm -f "${ARCHIVE}"
  echo "error: Sparkle ${VERSION} did not match its pinned checksum; nothing was unpacked" >&2
  exit 1
fi
mkdir -p "${DEST}"
tar -xJf "${ARCHIVE}" -C "${DEST}"
echo "${DEST}"
