#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="Daybook"
BUNDLE_ID="com.prabesh.daybook"
LOCAL_APP_DIR="${PROJECT_DIR}/${APP_NAME}.app"
PROMOTION_ROOT="${PROJECT_DIR}/.build"
PROMOTION_LOCK="${PROMOTION_ROOT}/promotion.lock"
CANDIDATE_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.$$"
BACKUP_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.backup.$$"
DEPLOYMENT_TARGET="14.0"
TARGET_TRIPLE="$(uname -m)-apple-macos${DEPLOYMENT_TARGET}"
# Raised by scripts/release.sh for each release. The build number must grow:
# it is what the updater compares.
APP_VERSION="1.0.1"
APP_BUILD="2"
# The updater checks this feed; the key verifies what it downloads. The
# matching private key lives in the Keychain (account Daybook).
UPDATE_FEED_URL="https://github.com/prabeshbhetwal/Daybook/releases/latest/download/appcast.xml"
UPDATE_PUBLIC_KEY="oVMwFmTRL3FCl/weIGgo7MQsJFRvSD7muBW936KkiQk="

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
SPARKLE_DIR="$("${PROJECT_DIR}/scripts/fetch-sparkle.sh")"

# Build only in an isolated directory. The local bundle remains untouched until
# compilation, signing, strict verification, and any requested self-test pass.
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX")"
LOCK_HELD=0

# Whatever stops the build, the previous local app is back in place and this
# run's leftovers are gone.
cleanup() {
  status=$?
  if [ -e "${BACKUP_APP_DIR}" ] && [ ! -e "${LOCAL_APP_DIR}" ]; then
    mv "${BACKUP_APP_DIR}" "${LOCAL_APP_DIR}" && echo "Restored the previous local app." >&2
  fi
  rm -rf "${STAGE_ROOT}" "${CANDIDATE_APP_DIR}"
  if [ -e "${LOCAL_APP_DIR}" ]; then rm -rf "${BACKUP_APP_DIR}"; fi
  if [ "${LOCK_HELD}" -eq 1 ]; then rmdir "${PROMOTION_LOCK}" || true; fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

APP_DIR="${STAGE_ROOT}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BINARY="${MACOS_DIR}/${APP_NAME}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# SessionEngine and SessionStore each span several files, so Swift's `private`
# can no longer keep their internals in. This does: no other file may call
# their helpers, read their bookkeeping, or set the state they publish.
# Arguments: the name callers use, the owning files' path prefix, the internal
# members, and the members only the owner may set.
keep_internals() {
  if grep -rnE "${1}\.(${3})([^A-Za-z0-9_]|$)|${1}\.(${4})[[:space:]]*[-+*/]?=[^=]" \
       Sources --include='*.swift' | grep -v "^${2}"; then
    echo "error: the lines above reach into the internals of ${2}*.swift; add a method there instead" >&2
    exit 1
  fi
}
keep_internals engine Sources/Core/SessionEngine \
  'absenceOutgrewCap|addPausedSpan|apply|applyExactCorrectionState|archiveCurrentSession|awayInterval|awayReturnedAt|beginFreshSession|cancelDwell|completeLongAway|continuedThread|correctionGeneration|decisionStartDate|departureApp|elapsed\(endingAt|endAbsentSession|endDeclaredAway|endIdlePause|endStretch|endWatchingPause|enterPause|holdSecondAbsence|interval|isAwaitingCorrection|isSelf|leavePause|legacyActiveRecordID|linkCreditRecords|liveCorrectionGeneration|liveGeneration|noteQuietWhileAwaiting|now|ownBundleID|pauseMeansNobodyHere|pauseStartDate|pausedSpans|pendingDwell|pendingRests|reconcileAwayReceipt|recordApp|recordAway|removePausedSpan|resolve|resolveAway|saveRests|scheduleDwell|schedulesDwell|secondAbsenceOutgrewCap|shadowAway|synchroniseCommittedCorrectionMetadata|transitionFrom[A-Za-z]*|transitionRevision|trustedPausedSpans|validateDecisionEffects|workBeforePendingAway' \
  'activeAutomaticAction|activeDetectedApp|activeIsAuto|activeRecordID|activeThreadID|activeThreadWasContinued|activeWorkType|awayDecisionError|awayDecisions|currentAppBundleID|currentAppName|lastAwayDecision|lastLongAwayTransition|pendingDecisionID|sessionStartDate|state|totalPausedDuration'
# PersistenceStore, also often called `store`, has its own automaticActivityRecord,
# savedActivities and state, so those three setters cannot be told apart here.
keep_internals store Sources/App/SessionStore \
  'LiveFrame|appliedDefaultWorkType|apply|cachedTypical|cachedTypicalMinute|deferredAutomationPending|earliestDayCache|historyAppLensCache|historySearchAppsCache|historySortedUsageCache|idle|lastLiveFrame|lastSampleWatching|pendingWakeActivation|presenceGate|refreshBreak|schedulesTicker|startTicker|stopTicker|tick|ticker|updateTicker|watchingCache|watchingEndedAt' \
  'activityAutomationError|breakCountdown|canUndoCorrection|correctionError|dashboardArchiveReadModelGeneration|dashboardReadModelGeneration|elapsed|goal|historyIndexGeneration|isBreakDue|longestToday|nextBreakTier|pendingActivityChoice|pendingAway|pendingAwayRange|previousSession|quickStarts|reviewReadModelGeneration|sessionsToday|streak|streakBest|threadElapsed|todayTotal|trackedToday|weekBars'

# Type comes from roles. A view names what its text is and
# Tokens.Typography fixes the size, weight and face; a raw size, a system text
# style or a reweighted role is how one role came to be drawn five ways. A
# weight may still change with state (`.weight(selected ? … : …)`).
type_outside_roles() {
  {
    grep -rnE '\.system\(size:|Font\.system\(|Typography\.Size\.|\.fontWeight\(|\.bold\(\)|Typography\.[A-Za-z]+[[:space:]]*\.weight\(\.' \
      Sources/App Sources/Design Sources/Surfaces --include='*.swift'
    grep -rnE 'font\(|Font' Sources/App Sources/Design Sources/Surfaces --include='*.swift' \
      | grep -E '[(?:][[:space:]]*\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)([^A-Za-z0-9_(]|$)'
  } | grep -v '^Sources/Design/Typography.swift:'
}
if type_outside_roles; then
  echo "error: the lines above set type outside Tokens.Typography; use a role from Sources/Design/Typography.swift" >&2
  exit 1
fi

# Lengths come from the zoom. A view takes a token or `N.zoomed` where a number
# becomes a length; a bare number there is how one surface came to ignore the
# setting. NUM is any number but 0 and 1 (hairlines are fixed by design), with
# `_` digit separators allowed. A line that is meant to stay fixed says
# `// zoom: fixed`.
lengths_outside_zoom() {
  local num='-?([2-9]|[1-9][0-9_]*[0-9]|1\.[0-9]*[1-9][0-9]*)(\.[0-9]+)?([^0-9._]|$)'
  local patterns=(
    "\.padding\(([^()]*, *)?${num}"
    "spacing: *${num}"
    "(^|[^A-Za-z])(width|height|minWidth|maxWidth|idealWidth|minHeight|maxHeight|idealHeight): *${num}"
    "cornerRadius: *${num}"
    "lineWidth: *${num}"
    "\.offset\(.*(x|y): *${num}"
    "(^|[^A-Za-z.])(size|diameter): *${num}"
    "(top|leading|bottom|trailing): *${num}"
  )
  local args=() pattern
  for pattern in "${patterns[@]}"; do args+=(-e "${pattern}"); done
  grep -rnE "${args[@]}" Sources/App Sources/Design Sources/Surfaces --include='*.swift' \
    | grep -v 'zoom: fixed'
}
if lengths_outside_zoom; then
  echo "error: the lines above set a length outside the zoom; use a token or N.zoomed (Sources/Design/Zoomed.swift)" >&2
  exit 1
fi

echo "Compiling for ${TARGET_TRIPLE}…"
SOURCE_FILES=()
while IFS= read -r source_file; do
  SOURCE_FILES+=("${source_file}")
done < <(find Sources -name '*.swift' -print | LC_ALL=C sort)

if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
  echo "error: no Swift source files found under Sources" >&2
  exit 1
fi

# The layers point one way, Core → App → Design/Surfaces, so Core must compile
# with nothing above it. Typecheck it alone beside the real build: it takes
# no extra wall time, and the full build alone cannot see a Core file using an
# App type.
find Sources/Core -name '*.swift' -exec swiftc -typecheck -parse-as-library \
  -swift-version 5 -warnings-as-errors -target "${TARGET_TRIPLE}" {} + &
CORE_CHECK=$!

# -Osize over -O: the code section is 41% smaller and the self-tests run no
# slower (measured 2026-09-30: 17.0s against 19.4s), so there is nothing to
# trade. The app is idle-bound; its speed is in what it does not do per tick.
swiftc \
  -Osize \
  -whole-module-optimization \
  -swift-version 5 \
  -warnings-as-errors \
  -parse-as-library \
  -target "${TARGET_TRIPLE}" \
  -framework Cocoa \
  -F "${SPARKLE_DIR}" \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "${BINARY}" \
  "${SOURCE_FILES[@]}"

if ! wait "${CORE_CHECK}"; then
  echo "error: Sources/Core does not compile on its own; move what it needs into Core" >&2
  exit 1
fi

# Local symbols are half the binary and serve only `sample` and crash reports.
# Strip them unless a profiling run asks to keep them: FC_KEEP_SYMBOLS=1.
if [ -z "${FC_KEEP_SYMBOLS:-}" ]; then
  strip -x "${BINARY}"
fi

# The updater ships inside the app. Copied without extended attributes or
# quarantine: the framework's symlinks carry com.apple.provenance, which
# codesign rejects as "detritus".
FRAMEWORKS_DIR="${APP_DIR}/Contents/Frameworks"
mkdir -p "${FRAMEWORKS_DIR}"
ditto --noextattr --noqtn "${SPARKLE_DIR}/Sparkle.framework" "${FRAMEWORKS_DIR}/Sparkle.framework"

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
	<string>${APP_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${APP_BUILD}</string>
	<key>SUFeedURL</key>
	<string>${UPDATE_FEED_URL}</string>
	<key>SUPublicEDKey</key>
	<string>${UPDATE_PUBLIC_KEY}</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUScheduledCheckInterval</key>
	<integer>604800</integer>
	<key>SUAllowsAutomaticUpdates</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>${DEPLOYMENT_TARGET}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Daybook listens only while you dictate a session note.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Spoken session notes are turned into text, on this Mac where your language allows it.</string>
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

# One promoter at a time. mkdir is atomic, so two builds cannot both hold it;
# a second build waits its turn.
# ponytail: a build killed with SIGKILL leaves the lock behind; remove it by
# hand when no build is running. Add owner-pid checks if that becomes common.
mkdir -p "${PROMOTION_ROOT}"
waited=0
until mkdir "${PROMOTION_LOCK}" 2>/dev/null; do
  if [ "${waited}" -eq 0 ]; then
    echo "Waiting for another build to finish replacing the local app…" >&2
  fi
  if [ "${waited}" -ge 600 ]; then
    echo "error: ${PROMOTION_LOCK} was held for two minutes." >&2
    echo "If no build is running, remove that directory and retry." >&2
    exit 1
  fi
  sleep 0.2
  waited=$((waited + 1))
done
LOCK_HELD=1

# Move the staged app next to the local one so the swap is a same-volume
# rename, and verify it there before anything is replaced.
mv "${APP_DIR}" "${CANDIDATE_APP_DIR}"
codesign --verify "${CANDIDATE_APP_DIR}"

if [ -e "${LOCAL_APP_DIR}" ]; then
  mv "${LOCAL_APP_DIR}" "${BACKUP_APP_DIR}"
fi
if ! mv "${CANDIDATE_APP_DIR}" "${LOCAL_APP_DIR}" \
    || ! codesign --verify "${LOCAL_APP_DIR}"; then
  echo "error: could not replace the local app with the verified build" >&2
  rm -rf "${LOCAL_APP_DIR}"
  exit 1
fi
rm -rf "${BACKUP_APP_DIR}"

LOCAL_BINARY="${LOCAL_APP_DIR}/Contents/MacOS/${APP_NAME}"
SIZE="$(du -h "${LOCAL_BINARY}" | cut -f1 | tr -d ' ')"
echo "Binary: ${LOCAL_BINARY} (${SIZE})"
echo "Build succeeded: ${LOCAL_APP_DIR}"

# The app itself, from any folder: a process named for it that is not one
# of its own test runs. Searching command lines instead matched other
# builds' compilers, whose arguments hold the same path, so a relaunch
# quit the app and then refused to open the new one.
app_pids() {
  for pid in $(pgrep -x "${APP_NAME}"); do
    case "$(ps -o args= -p "${pid}" 2>/dev/null)" in
      *--selftest*|*--snapshot*|*--gallery*|*--fixture-window*) ;;
      *) echo "${pid}" ;;
    esac
  done
}
local_app_running() {
  for pid in $(app_pids); do
    case "$(ps -o args= -p "${pid}" 2>/dev/null)" in
      "${LOCAL_APP_DIR}/Contents/MacOS/${APP_NAME}"*) return 0 ;;
    esac
  done
  return 1
}

# A copy started from this folder is still running from the files the swap
# just deleted. macOS can no longer find its path, so turning on Open at
# login fails with "Invalid argument". Finish the swap the way --run does.
if [ "${RUN}" -eq 0 ] && local_app_running; then
  echo "Relaunching ${APP_NAME}: the copy running from here was just replaced."
  RUN=1
fi

if [ "${RUN}" -eq 1 ]; then
  # A checkout under an iCloud-synced folder is re-quarantined after this
  # script's own xattr -cr, and Launch Services then runs a translocated,
  # read-only copy at a random path: stale after the next build, and not
  # findable by its path to quit. This is our own build product. Strip it
  # again at the last moment, right before opening.
  xattr -dr com.apple.quarantine "${LOCAL_APP_DIR}" 2>/dev/null || true
  # `open` on a running app only brings it forward: the old process keeps
  # its old code while the new binary sits unused on disk. Quit any running
  # copy, from any folder, the ordinary way so it saves on the way out.
  osascript -e "quit app id \"${BUNDLE_ID}\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 100); do
    [ -z "$(app_pids)" ] && break
    sleep 0.1
  done
  if [ -n "$(app_pids)" ]; then
    echo "error: a running ${APP_NAME} did not quit within 10s; quit it, then run again" >&2
    exit 1
  fi
  # Launch Services can drop an open that lands while the quit copy is still
  # being torn down, and `open` reports success either way: wait for the new
  # process, and ask once more if none appears.
  launched=0
  for attempt in 1 2; do
    open "${LOCAL_APP_DIR}"
    for _ in $(seq 1 50); do
      if local_app_running; then launched=1; break; fi
      sleep 0.1
    done
    [ "${launched}" -eq 1 ] && break
  done
  if [ "${launched}" -ne 1 ]; then
    echo "error: ${APP_NAME} did not start; open it from ${LOCAL_APP_DIR}" >&2
    exit 1
  fi
  echo "Launched ${APP_NAME}."
fi
