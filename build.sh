#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FocusContinuity"
BUNDLE_ID="com.prabesh.focuscontinuity"
APP_DIR="${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BINARY="${MACOS_DIR}/${APP_NAME}"
DEPLOYMENT_TARGET="13.0"
HOST_ARCH="$(uname -m)"
TARGET_TRIPLE="${HOST_ARCH}-apple-macos${DEPLOYMENT_TARGET}"

RUN=0
TEST=0
for arg in "$@"; do
  case "$arg" in
    --run)  RUN=1 ;;
    --test) TEST=1 ;;
    *) echo "usage: $0 [--run] [--test]" >&2; exit 2 ;;
  esac
done

# 1. Clean and recreate the bundle skeleton.
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 2. Compile.
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

# 3. App icon. Optional: if Assets/AppIcon.png exists it is rendered into a full
#    .icns. The app is LSUIElement so this never appears in the Dock — it shows
#    in Finder, Get Info, and on the extended-break alert.
ICON_SOURCE="Assets/AppIcon.png"
ICON_KEYS=""
if [ -f "${ICON_SOURCE}" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "${ICONSET}"

  WIDTH="$(sips -g pixelWidth "${ICON_SOURCE}" | awk '/pixelWidth/{print $2}')"
  HEIGHT="$(sips -g pixelHeight "${ICON_SOURCE}" | awk '/pixelHeight/{print $2}')"
  SQUARE="${ICON_SOURCE}"
  if [ "${WIDTH}" != "${HEIGHT}" ]; then
    SIDE="${WIDTH}"; [ "${HEIGHT}" -lt "${WIDTH}" ] && SIDE="${HEIGHT}"
    SQUARE="$(dirname "${ICONSET}")/square.png"
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
  rm -rf "$(dirname "${ICONSET}")"
  ICON_KEYS=$'\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>\n\t<key>CFBundleIconName</key>\n\t<string>AppIcon</string>'
  echo "Icon: ${RESOURCES_DIR}/AppIcon.icns"
else
  echo "No ${ICON_SOURCE} found — building without an app icon." >&2
fi

# 4. Info.plist.
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

# 5. Ad-hoc signature. codesign rejects any resource fork / Finder metadata the
#    filesystem attached, and a file provider (iCloud Desktop, Dropbox, …) can
#    re-stamp the bundle in the window between stripping and signing — so retry
#    rather than leaving a half-signed bundle behind.
signed=0
for attempt in 1 2 3 4 5 6; do
  xattr -cr "${APP_DIR}"
  if codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null; then
    signed=1
    break
  fi
  echo "codesign attempt ${attempt} failed (extended attributes re-applied); retrying…" >&2
  sleep 0.3
done

if [ "${signed}" -ne 1 ] || ! codesign --verify "${APP_DIR}" 2>/dev/null; then
  echo "error: could not produce a verifiable signature; removing ${APP_DIR}" >&2
  rm -rf "${APP_DIR}"
  exit 1
fi

SIZE="$(du -h "${BINARY}" | cut -f1 | tr -d ' ')"
echo "Binary: ${BINARY} (${SIZE})"
echo "Build succeeded: ${APP_DIR}"

if [ "${TEST}" -eq 1 ]; then
  echo
  "${BINARY}" --selftest
fi

if [ "${RUN}" -eq 1 ]; then
  open "${APP_DIR}"
  echo "Launched ${APP_NAME}."
fi
