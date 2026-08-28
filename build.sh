#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="FocusContinuity"
BUNDLE_ID="com.prabesh.focuscontinuity"
LOCAL_APP_DIR="${PROJECT_DIR}/${APP_NAME}.app"
DEPLOYMENT_TARGET="13.0"
HOST_ARCH="$(uname -m)"
TARGET_TRIPLE="${HOST_ARCH}-apple-macos${DEPLOYMENT_TARGET}"

RUN=0
TEST=0
CHECK=0
for arg in "$@"; do
  case "$arg" in
    --run)   RUN=1 ;;
    --test)  TEST=1 ;;
    --check) CHECK=1; TEST=1 ;;
    *) echo "usage: $0 [--run] [--test] [--check]" >&2; exit 2 ;;
  esac
done

# Build only in an isolated directory. The local bundle remains untouched until
# compilation, signing, strict verification, and any requested self-test pass.
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX")"
cleanup_stage() {
  rm -rf "${STAGE_ROOT}"
}
trap cleanup_stage EXIT

APP_DIR="${STAGE_ROOT}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BINARY="${MACOS_DIR}/${APP_NAME}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "Compiling for ${TARGET_TRIPLE}…"
swiftc \
  -O \
  -whole-module-optimization \
  -swift-version 5 \
  -warnings-as-errors \
  -parse-as-library \
  -target "${TARGET_TRIPLE}" \
  -framework Cocoa \
  -o "${BINARY}" \
  $(find Sources -name '*.swift' | sort)

# Optional app icon. The app is LSUIElement, so it never appears in the Dock.
ICON_SOURCE="Assets/AppIcon.png"
ICON_KEYS=""
if [ -f "${ICON_SOURCE}" ]; then
  ICONSET_ROOT="${STAGE_ROOT}/icon-build"
  ICONSET="${ICONSET_ROOT}/AppIcon.iconset"
  mkdir -p "${ICONSET}"

  WIDTH="$(sips -g pixelWidth "${ICON_SOURCE}" | awk '/pixelWidth/{print $2}')"
  HEIGHT="$(sips -g pixelHeight "${ICON_SOURCE}" | awk '/pixelHeight/{print $2}')"
  SQUARE="${ICON_SOURCE}"
  if [ "${WIDTH}" != "${HEIGHT}" ]; then
    SIDE="${WIDTH}"; [ "${HEIGHT}" -lt "${WIDTH}" ] && SIDE="${HEIGHT}"
    SQUARE="${ICONSET_ROOT}/square.png"
    echo "Icon source is ${WIDTH}x${HEIGHT}; centre-cropping to ${SIDE}x${SIDE}." >&2
    sips -c "${SIDE}" "${SIDE}" "${ICON_SOURCE}" --out "${SQUARE}" >/dev/null
  fi

  for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
              "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
              "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    size="${spec%% *}"
    name="${spec##* }"
    sips -s format png -z "${size}" "${size}" "${SQUARE}" \
      --out "${ICONSET}/${name}.png" >/dev/null
  done

  iconutil -c icns "${ICONSET}" -o "${RESOURCES_DIR}/AppIcon.icns"
  rm -rf "${ICONSET_ROOT}"
  ICON_KEYS=$'\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>\n\t<key>CFBundleIconName</key>\n\t<string>AppIcon</string>'
  echo "Icon: ${RESOURCES_DIR}/AppIcon.icns"
else
  echo "No ${ICON_SOURCE} found — building without an app icon." >&2
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>${DEPLOYMENT_TARGET}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
${ICON_KEYS}
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# Filesystem metadata can be re-applied by a file provider. Clear it both
# immediately before signing and immediately before strict verification.
signed=0
for attempt in 1 2 3 4 5 6; do
  xattr -cr "${APP_DIR}"
  if codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null; then
    xattr -cr "${APP_DIR}"
    if codesign --verify --deep --strict "${APP_DIR}" 2>/dev/null; then
      signed=1
      break
    fi
  fi
  echo "codesign attempt ${attempt} failed (extended attributes re-applied); retrying…" >&2
  sleep 0.3
done

if [ "${signed}" -ne 1 ]; then
  echo "error: could not produce a strictly verifiable staged signature" >&2
  exit 1
fi

if [ "${TEST}" -eq 1 ]; then
  echo
  "${BINARY}" --selftest
fi

if [ "${CHECK}" -eq 1 ]; then
  SIZE="$(du -h "${BINARY}" | cut -f1 | tr -d ' ')"
  echo "Check succeeded: staged ${APP_DIR} (${SIZE}); local bundle was not promoted."
  exit 0
fi

rm -rf "${LOCAL_APP_DIR}"
mv "${APP_DIR}" "${LOCAL_APP_DIR}"

if ! codesign --verify "${LOCAL_APP_DIR}" 2>/dev/null; then
  echo "error: promoted app did not pass ordinary signature verification" >&2
  exit 1
fi

LOCAL_BINARY="${LOCAL_APP_DIR}/Contents/MacOS/${APP_NAME}"
SIZE="$(du -h "${LOCAL_BINARY}" | cut -f1 | tr -d ' ')"
echo "Binary: ${LOCAL_BINARY} (${SIZE})"
echo "Build succeeded: ${LOCAL_APP_DIR}"

if [ "${RUN}" -eq 1 ]; then
  open "${LOCAL_APP_DIR}"
  echo "Launched ${APP_NAME}."
fi
