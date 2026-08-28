#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="FocusContinuity"
BUNDLE_ID="com.prabesh.focuscontinuity"
LOCAL_APP_DIR="${PROJECT_DIR}/${APP_NAME}.app"
PROMOTION_ROOT="${PROJECT_DIR}/.build"
CANDIDATE_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.candidate"
BACKUP_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.backup"
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
PROMOTION_IN_PROGRESS=0
PROMOTION_COMPLETE=0
LOCAL_APP_WAS_PRESENT=0

restore_previous_app() {
  if [ -e "${BACKUP_APP_DIR}" ]; then
    if [ -e "${LOCAL_APP_DIR}" ]; then
      rm -rf "${LOCAL_APP_DIR}"
    fi
    if ! mv "${BACKUP_APP_DIR}" "${LOCAL_APP_DIR}"; then
      echo "error: could not restore the previous local app from ${BACKUP_APP_DIR}" >&2
      return 1
    fi
    return 0
  fi

  if [ "${LOCAL_APP_WAS_PRESENT}" -eq 0 ]; then
    rm -rf "${LOCAL_APP_DIR}"
    return 0
  fi

  if [ -e "${LOCAL_APP_DIR}" ]; then
    echo "warning: backup is absent; preserving the existing local app" >&2
    return 0
  fi

  echo "error: previous local app and backup are both absent; cannot roll back" >&2
  return 1
}

rollback_failed_promotion() {
  if restore_previous_app; then
    PROMOTION_IN_PROGRESS=0
    return 0
  fi
  return 1
}

cleanup_build() {
  cleanup_status=$?
  trap - EXIT

  if [ "${PROMOTION_IN_PROGRESS}" -eq 1 ] && [ "${PROMOTION_COMPLETE}" -ne 1 ]; then
    restore_previous_app || cleanup_status=1
  fi

  rm -rf "${STAGE_ROOT}"
  rm -rf "${CANDIDATE_APP_DIR}"
  if [ "${PROMOTION_COMPLETE}" -eq 1 ]; then
    rm -rf "${BACKUP_APP_DIR}"
  fi
  exit "${cleanup_status}"
}

handle_signal() {
  signal_name="$1"
  signal_status="$2"
  trap - INT TERM HUP
  echo "received ${signal_name}; rolling back any in-progress promotion" >&2
  exit "${signal_status}"
}

trap cleanup_build EXIT
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
trap 'handle_signal HUP 129' HUP

APP_DIR="${STAGE_ROOT}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BINARY="${MACOS_DIR}/${APP_NAME}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "Compiling for ${TARGET_TRIPLE}…"
SOURCE_FILES=()
while IFS= read -r source_file; do
  SOURCE_FILES+=("${source_file}")
done < <(find Sources -name '*.swift' -print | LC_ALL=C sort)

if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
  echo "error: no Swift source files found under Sources" >&2
  exit 1
fi

swiftc \
  -O \
  -whole-module-optimization \
  -swift-version 5 \
  -warnings-as-errors \
  -parse-as-library \
  -target "${TARGET_TRIPLE}" \
  -framework Cocoa \
  -o "${BINARY}" \
  "${SOURCE_FILES[@]}"

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
SIGNING_LOG="${STAGE_ROOT}/codesign-attempt.log"
SIGNING_FAILURE=""
for attempt in 1 2 3 4 5 6; do
  : > "${SIGNING_LOG}"
  xattr -cr "${APP_DIR}"
  if codesign --force --deep --sign - "${APP_DIR}" 2>"${SIGNING_LOG}"; then
    xattr -cr "${APP_DIR}"
    if codesign --verify --deep --strict "${APP_DIR}" 2>>"${SIGNING_LOG}"; then
      signed=1
      break
    else
      SIGNING_FAILURE="strict staged signature verification"
    fi
  else
    SIGNING_FAILURE="ad-hoc signing"
  fi
  echo "${SIGNING_FAILURE} failed on attempt ${attempt}; retrying…" >&2
  sleep 0.3
done

if [ "${signed}" -ne 1 ]; then
  echo "error: ${SIGNING_FAILURE:-staged signing} failed after 6 attempts" >&2
  if [ -s "${SIGNING_LOG}" ]; then
    sed 's/^/codesign: /' "${SIGNING_LOG}" >&2
  else
    echo "codesign: no diagnostic output" >&2
  fi
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

ORDINARY_VERIFY_LOG="${STAGE_ROOT}/ordinary-verify.log"
verify_ordinary_signature() {
  bundle_path="$1"
  bundle_label="$2"
  : > "${ORDINARY_VERIFY_LOG}"
  if ! codesign --verify "${bundle_path}" 2>"${ORDINARY_VERIFY_LOG}"; then
    echo "error: ${bundle_label} did not pass ordinary signature verification" >&2
    if [ -s "${ORDINARY_VERIFY_LOG}" ]; then
      sed 's/^/codesign: /' "${ORDINARY_VERIFY_LOG}" >&2
    else
      echo "codesign: no diagnostic output" >&2
    fi
    return 1
  fi
}

prepare_promotion_directory() {
  mkdir -p "${PROMOTION_ROOT}"
  rm -rf "${CANDIDATE_APP_DIR}"

  if [ ! -e "${BACKUP_APP_DIR}" ]; then
    return 0
  fi

  if [ ! -e "${LOCAL_APP_DIR}" ]; then
    if ! verify_ordinary_signature "${BACKUP_APP_DIR}" "stale local-app backup"; then
      echo "error: local app is absent and the stale backup is not verifiable; preserving the backup" >&2
      return 1
    fi
    echo "Recovering missing local app from ${BACKUP_APP_DIR}." >&2
    mv "${BACKUP_APP_DIR}" "${LOCAL_APP_DIR}"
    return
  fi

  if verify_ordinary_signature "${LOCAL_APP_DIR}" "existing local app before stale-backup cleanup"; then
    rm -rf "${BACKUP_APP_DIR}"
    return
  fi

  if ! verify_ordinary_signature "${BACKUP_APP_DIR}" "stale local-app backup"; then
    echo "error: existing local app and stale backup both failed ordinary verification; preserving both" >&2
    return 1
  fi

  echo "Restoring verified stale backup over invalid local app." >&2
  rm -rf "${LOCAL_APP_DIR}"
  mv "${BACKUP_APP_DIR}" "${LOCAL_APP_DIR}"
}

if ! prepare_promotion_directory; then
  echo "error: could not prepare the local promotion directory" >&2
  exit 1
fi

if ! mv "${APP_DIR}" "${CANDIDATE_APP_DIR}"; then
  echo "error: could not move the staged app to ${CANDIDATE_APP_DIR}" >&2
  exit 1
fi

if ! verify_ordinary_signature "${CANDIDATE_APP_DIR}" "promotion candidate"; then
  exit 1
fi

if [ -e "${LOCAL_APP_DIR}" ]; then
  LOCAL_APP_WAS_PRESENT=1
fi
PROMOTION_IN_PROGRESS=1

if [ "${LOCAL_APP_WAS_PRESENT}" -eq 1 ]; then
  if ! mv "${LOCAL_APP_DIR}" "${BACKUP_APP_DIR}"; then
    echo "error: could not move the previous local app to ${BACKUP_APP_DIR}" >&2
    rollback_failed_promotion || true
    exit 1
  fi
fi

if ! mv "${CANDIDATE_APP_DIR}" "${LOCAL_APP_DIR}"; then
  echo "error: could not replace the local app with the verified candidate" >&2
  rollback_failed_promotion || true
  exit 1
fi

if ! verify_ordinary_signature "${LOCAL_APP_DIR}" "promoted local app"; then
  rollback_failed_promotion || true
  exit 1
fi

PROMOTION_COMPLETE=1
PROMOTION_IN_PROGRESS=0
rm -rf "${BACKUP_APP_DIR}"

LOCAL_BINARY="${LOCAL_APP_DIR}/Contents/MacOS/${APP_NAME}"
SIZE="$(du -h "${LOCAL_BINARY}" | cut -f1 | tr -d ' ')"
echo "Binary: ${LOCAL_BINARY} (${SIZE})"
echo "Build succeeded: ${LOCAL_APP_DIR}"

if [ "${RUN}" -eq 1 ]; then
  open "${LOCAL_APP_DIR}"
  echo "Launched ${APP_NAME}."
fi
