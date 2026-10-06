#!/bin/bash
set -euo pipefail

# Builds a separate, fixture-only executable, never a copy of the production
# executable with temporary flags. A flagless relaunch cannot start recording.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_SCENARIO="${1:-storyDay}"
if [ "$#" -gt 1 ] || [[ ! "${FIXTURE_SCENARIO}" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
  echo "usage: $0 [SnapshotScenario]" >&2
  exit 2
fi
LOCAL_APP="${PROJECT_DIR}/Daybook.app"
if [ ! -f "${LOCAL_APP}/Contents/Info.plist" ]; then
  echo "Build the local app first with ./build.sh --test." >&2
  exit 2
fi

# The fixture's source set includes the updater, so it links Sparkle exactly as
# build.sh does. Fetched before anything is created, so a failed fetch leaves
# nothing behind.
SPARKLE_DIR="$("${PROJECT_DIR}/scripts/fetch-sparkle.sh")"

mkdir -p "${PROJECT_DIR}/.build"
FIXTURE_ROOT="$(mktemp -d "${PROJECT_DIR}/.build/native-fixture.XXXXXX")"
FIXTURE_APP="${FIXTURE_ROOT}/Daybook.app"
mkdir -p "${FIXTURE_APP}/Contents/MacOS"
cp "${LOCAL_APP}/Contents/Info.plist" "${FIXTURE_APP}/Contents/Info.plist"
ditto --noextattr --norsrc "${LOCAL_APP}/Contents/Resources" "${FIXTURE_APP}/Contents/Resources"
FIXTURE_ID="com.prabesh.daybook.verification.${FIXTURE_ROOT##*.}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${FIXTURE_ID}" "${FIXTURE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Daybook Verification' "${FIXTURE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "${FIXTURE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :FCVerificationScenario string ${FIXTURE_SCENARIO}" "${FIXTURE_APP}/Contents/Info.plist"

SOURCE_FILES=()
while IFS= read -r source_file; do
  if [ "${source_file##*/}" != "DaybookApp.swift" ]; then
    SOURCE_FILES+=("${source_file}")
  fi
done < <(find "${PROJECT_DIR}/Sources" -name '*.swift' -print | LC_ALL=C sort)

swiftc -O -swift-version 5 -warnings-as-errors -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" -framework Cocoa \
  -F "${SPARKLE_DIR}" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "${SOURCE_FILES[@]}" "${PROJECT_DIR}/scripts/NativeFixtureMain.swift" \
  -o "${FIXTURE_APP}/Contents/MacOS/Daybook"
# Copied without extended attributes or quarantine, as build.sh does.
mkdir -p "${FIXTURE_APP}/Contents/Frameworks"
ditto --noextattr --noqtn "${SPARKLE_DIR}/Sparkle.framework" "${FIXTURE_APP}/Contents/Frameworks/Sparkle.framework"
# Only this newly created bundle is touched; no live data or root app changes.
xattr -cr "${FIXTURE_APP}"
codesign --force --deep --sign - "${FIXTURE_APP}"
codesign --verify --deep --strict "${FIXTURE_APP}"
echo "Fixture-only app (${FIXTURE_SCENARIO}): ${FIXTURE_APP}"
