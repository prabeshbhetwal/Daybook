#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="FocusContinuity"
BUNDLE_ID="com.prabesh.focuscontinuity"
LOCAL_APP_DIR="${PROJECT_DIR}/${APP_NAME}.app"
PROMOTION_ROOT="${PROJECT_DIR}/.build"
RUN_ID="$$-$(date +%s)-${RANDOM}"
CANDIDATE_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${RUN_ID}"
BACKUP_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${RUN_ID}"
OWNER_MARKER="${PROMOTION_ROOT}/promotion-owner.${RUN_ID}"
PROMOTION_LOCK="${PROMOTION_ROOT}/promotion.lock"
RECOVERY_GUARD="${PROMOTION_ROOT}/promotion-recovery.lock"
RECOVERY_GUARD_OWNER="${RECOVERY_GUARD}/owner"
LEGACY_CANDIDATE_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.candidate"
LEGACY_BACKUP_APP_DIR="${PROMOTION_ROOT}/${APP_NAME}.app.backup"
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
PROMOTION_LOCK_HELD=0
PROMOTION_PATHS_TOUCHED=0
PRESERVE_PROMOTION_LOCK=0
RECOVERY_GUARD_HELD=0
PRESERVE_RECOVERY_GUARD=0

recovery_guard_exists() {
  [ -e "${RECOVERY_GUARD}" ] || [ -L "${RECOVERY_GUARD}" ]
}

recovery_guard_owned_by_current_run() {
  if [ ! -f "${RECOVERY_GUARD_OWNER}" ]; then
    return 1
  fi
  guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD_OWNER}" | head -n 1)"
  guard_run_id="$(sed -n 's/^run_id=//p' "${RECOVERY_GUARD_OWNER}" | head -n 1)"
  [ "${guard_pid}" = "$$" ] && [ "${guard_run_id}" = "${RUN_ID}" ]
}

release_recovery_guard() {
  if [ "${RECOVERY_GUARD_HELD}" -ne 1 ]; then
    return 0
  fi

  if [ "${PRESERVE_RECOVERY_GUARD}" -eq 0 ] \
      && recovery_guard_owned_by_current_run; then
    rm -f "${RECOVERY_GUARD_OWNER}"
    if ! rmdir "${RECOVERY_GUARD}" 2>/dev/null; then
      if [ -d "${RECOVERY_GUARD}" ]; then
        printf 'pid=%s\nrun_id=%s\n' "$$" "${RUN_ID}" \
          > "${RECOVERY_GUARD_OWNER}" || true
      fi
      echo "warning: could not release the owned promotion recovery guard; preserving it" >&2
    fi
  fi
  RECOVERY_GUARD_HELD=0
}

release_promotion_lock() {
  if [ "${PROMOTION_LOCK_HELD}" -eq 1 ]; then
    if [ "${PRESERVE_PROMOTION_LOCK}" -eq 0 ] \
        && [ -e "${OWNER_MARKER}" ] && [ -e "${PROMOTION_LOCK}" ] \
        && [ "${OWNER_MARKER}" -ef "${PROMOTION_LOCK}" ]; then
      rm -f "${PROMOTION_LOCK}"
    fi
    PROMOTION_LOCK_HELD=0
  fi
  if [ "${PROMOTION_PATHS_TOUCHED}" -eq 1 ]; then
    rm -f "${OWNER_MARKER}"
  fi
}

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
    if ! restore_previous_app; then
      cleanup_status=1
      # Keep the ownership record and per-run backup/candidate so the next
      # promoter can retry recovery instead of losing the rollback source.
      PRESERVE_PROMOTION_LOCK=1
    fi
  fi

  rm -rf "${STAGE_ROOT}"
  if [ "${PROMOTION_PATHS_TOUCHED}" -eq 1 ] \
      && [ "${PRESERVE_PROMOTION_LOCK}" -eq 0 ]; then
    rm -rf "${CANDIDATE_APP_DIR}"
    if [ "${PROMOTION_COMPLETE}" -eq 1 ]; then
      rm -rf "${BACKUP_APP_DIR}"
    fi
  fi
  release_recovery_guard
  release_promotion_lock
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

recover_transaction_paths() {
  stale_candidate="$1"
  stale_backup="$2"
  stale_label="$3"

  if [ -e "${stale_backup}" ]; then
    if [ ! -e "${LOCAL_APP_DIR}" ]; then
      if ! verify_ordinary_signature "${stale_backup}" "${stale_label} backup"; then
        echo "error: local app is absent and the ${stale_label} backup is not verifiable; preserving recovery files" >&2
        return 1
      fi
      echo "Recovering missing local app from ${stale_backup}." >&2
      mv "${stale_backup}" "${LOCAL_APP_DIR}"
    elif verify_ordinary_signature "${LOCAL_APP_DIR}" \
        "existing local app before ${stale_label} cleanup"; then
      rm -rf "${stale_backup}"
    else
      if ! verify_ordinary_signature "${stale_backup}" "${stale_label} backup"; then
        echo "error: existing local app and ${stale_label} backup both failed ordinary verification; preserving recovery files" >&2
        return 1
      fi
      echo "Restoring verified ${stale_label} backup over invalid local app." >&2
      rm -rf "${LOCAL_APP_DIR}"
      mv "${stale_backup}" "${LOCAL_APP_DIR}"
    fi
    rm -rf "${stale_candidate}"
    return 0
  fi

  if [ ! -e "${stale_candidate}" ]; then
    return 0
  fi
  if ! verify_ordinary_signature "${stale_candidate}" "${stale_label} candidate"; then
    echo "error: ${stale_label} candidate is not verifiable; preserving it" >&2
    return 1
  fi
  if [ ! -e "${LOCAL_APP_DIR}" ]; then
    echo "Recovering verified ${stale_label} candidate as the local app." >&2
    mv "${stale_candidate}" "${LOCAL_APP_DIR}"
    return 0
  fi
  if verify_ordinary_signature "${LOCAL_APP_DIR}" \
      "existing local app before ${stale_label} candidate cleanup"; then
    rm -rf "${stale_candidate}"
    return 0
  fi
  echo "Replacing invalid local app with verified ${stale_label} candidate." >&2
  rm -rf "${LOCAL_APP_DIR}"
  mv "${stale_candidate}" "${LOCAL_APP_DIR}"
}

valid_run_id() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

owner_field() {
  field_name="$1"
  owner_file="$2"
  sed -n "s/^${field_name}=//p" "${owner_file}" | head -n 1
}

lock_identity() {
  stat -f '%d:%i' "$1" 2>/dev/null
}

read_lock_snapshot() {
  snapshot_file="$1"
  snapshot_identity_before="$(lock_identity "${snapshot_file}")" || return 1
  SNAPSHOT_PID="$(owner_field pid "${snapshot_file}")"
  SNAPSHOT_RUN_ID="$(owner_field run_id "${snapshot_file}")"
  SNAPSHOT_STARTED="$(owner_field started "${snapshot_file}")"
  snapshot_identity_after="$(lock_identity "${snapshot_file}")" || return 1
  if [ "${snapshot_identity_before}" != "${snapshot_identity_after}" ]; then
    return 1
  fi
  SNAPSHOT_IDENTITY="${snapshot_identity_before}"
}

acquire_recovery_guard() {
  if ! mkdir "${RECOVERY_GUARD}" 2>/dev/null; then
    echo "error: another process is recovering a stale promotion lock" >&2
    return 1
  fi
  RECOVERY_GUARD_HELD=1
  if ! printf 'pid=%s\nrun_id=%s\n' "$$" "${RUN_ID}" \
      > "${RECOVERY_GUARD_OWNER}"; then
    PRESERVE_RECOVERY_GUARD=1
    echo "error: could not record promotion recovery guard ownership; preserving the guard" >&2
    return 1
  fi
}

acquire_promotion_lock() {
  mkdir -p "${PROMOTION_ROOT}"
  PROMOTION_PATHS_TOUCHED=1
  printf 'pid=%s\nrun_id=%s\nstarted=%s\n' \
    "$$" "${RUN_ID}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${OWNER_MARKER}"

  while true; do
    if recovery_guard_exists; then
      echo "error: another process is recovering a stale promotion lock" >&2
      return 1
    fi
    if ln "${OWNER_MARKER}" "${PROMOTION_LOCK}" 2>/dev/null; then
      PROMOTION_LOCK_HELD=1
      if recovery_guard_exists; then
        echo "error: another process is recovering a stale promotion lock" >&2
        release_promotion_lock
        return 1
      fi
      return 0
    fi
    if [ ! -f "${PROMOTION_LOCK}" ]; then
      echo "error: promotion lock exists without a readable ownership marker; preserving it" >&2
      return 1
    fi

    if ! read_lock_snapshot "${PROMOTION_LOCK}"; then
      echo "error: promotion lock changed while its ownership was read; preserving it" >&2
      return 1
    fi
    lock_pid="${SNAPSHOT_PID}"
    lock_run_id="${SNAPSHOT_RUN_ID}"
    lock_started="${SNAPSHOT_STARTED}"
    lock_snapshot_identity="${SNAPSHOT_IDENTITY}"
    case "${lock_pid}" in
      ""|*[!0-9]*)
        echo "error: promotion lock has an invalid owner PID; preserving it" >&2
        return 1
        ;;
    esac
    if kill -0 "${lock_pid}" 2>/dev/null; then
      echo "error: promotion lock is held by live process ${lock_pid} (run ${lock_run_id:-unknown}, started ${lock_started:-unknown})" >&2
      return 1
    fi
    if ! valid_run_id "${lock_run_id}"; then
      echo "error: stale promotion lock has an invalid run id; preserving it" >&2
      return 1
    fi

    echo "Recovering stale promotion lock owned by process ${lock_pid} (run ${lock_run_id})." >&2
    if ! acquire_recovery_guard; then
      return 1
    fi
    if ! read_lock_snapshot "${PROMOTION_LOCK}" \
        || [ "${SNAPSHOT_PID}" != "${lock_pid}" ] \
        || [ "${SNAPSHOT_RUN_ID}" != "${lock_run_id}" ] \
        || [ "${SNAPSHOT_STARTED}" != "${lock_started}" ] \
        || [ "${SNAPSHOT_IDENTITY}" != "${lock_snapshot_identity}" ]; then
      echo "error: stale promotion lock changed before recovery admission; preserving it" >&2
      return 1
    fi
    if ! recovery_guard_owned_by_current_run; then
      PRESERVE_RECOVERY_GUARD=1
      echo "error: promotion recovery guard ownership is unverifiable; preserving recovery evidence" >&2
      return 1
    fi

    # Preserve the guard across the unlink/link crash point. Stamp the
    # replacement with the stale run until recovery completes, so signal
    # cleanup leaves the rollback paths discoverable by the next promoter.
    replacement_started="$(owner_field started "${OWNER_MARKER}")"
    printf 'pid=%s\nrun_id=%s\nstarted=%s\n' \
      "$$" "${lock_run_id}" "${lock_started:-unknown}" > "${OWNER_MARKER}"
    PRESERVE_RECOVERY_GUARD=1
    PRESERVE_PROMOTION_LOCK=1
    if ! rm -f "${PROMOTION_LOCK}"; then
      echo "error: could not remove the admitted stale promotion lock; preserving the recovery guard" >&2
      return 1
    fi

    # A promoter that passed its pre-link guard check before our mkdir can
    # transiently occupy the empty primary path. Never remove that inode: its
    # post-link check will observe our guard and release its own hard link.
    # Re-evaluate ownership until the path clears, with a bound only to avoid
    # waiting forever on a live process that does not honour the protocol.
    replacement_checks=0
    while true; do
      if ! recovery_guard_owned_by_current_run; then
        PRESERVE_RECOVERY_GUARD=1
        echo "error: promotion recovery guard ownership changed during primary replacement; preserving recovery evidence" >&2
        return 1
      fi
      if [ ! -f "${OWNER_MARKER}" ]; then
        echo "error: recovery owner marker disappeared during primary replacement; preserving recovery evidence" >&2
        return 1
      fi
      if ln "${OWNER_MARKER}" "${PROMOTION_LOCK}" 2>/dev/null; then
        break
      fi
      if [ -e "${PROMOTION_LOCK}" ] \
          && [ "${OWNER_MARKER}" -ef "${PROMOTION_LOCK}" ]; then
        break
      fi

      replacement_checks=$((replacement_checks + 1))
      if [ -e "${PROMOTION_LOCK}" ] || [ -L "${PROMOTION_LOCK}" ]; then
        competing_snapshot_read=0
        if [ -f "${PROMOTION_LOCK}" ] \
            && read_lock_snapshot "${PROMOTION_LOCK}"; then
          competing_snapshot_read=1
        elif [ -e "${PROMOTION_LOCK}" ] || [ -L "${PROMOTION_LOCK}" ]; then
          echo "error: competing promotion lock is unverifiable; preserving recovery evidence" >&2
          return 1
        fi
      else
        competing_snapshot_read=0
      fi
      if [ "${competing_snapshot_read}" -eq 1 ]; then
        competing_pid="${SNAPSHOT_PID}"
        competing_run_id="${SNAPSHOT_RUN_ID}"
        competing_started="${SNAPSHOT_STARTED}"
        case "${competing_pid}" in
          ""|*[!0-9]*)
            echo "error: competing promotion lock has an invalid owner PID; preserving recovery evidence" >&2
            return 1
            ;;
        esac
        if ! valid_run_id "${competing_run_id}" \
            || [ -z "${competing_started}" ]; then
          echo "error: competing promotion lock ownership is incomplete; preserving recovery evidence" >&2
          return 1
        fi
        if ! kill -0 "${competing_pid}" 2>/dev/null; then
          if [ -e "${PROMOTION_LOCK}" ] || [ -L "${PROMOTION_LOCK}" ]; then
            current_competing_identity="$(lock_identity "${PROMOTION_LOCK}")" || {
              echo "error: competing promotion lock became unverifiable; preserving recovery evidence" >&2
              return 1
            }
            if [ "${current_competing_identity}" = "${SNAPSHOT_IDENTITY}" ]; then
              echo "error: competing promotion lock owner is not live; preserving recovery evidence" >&2
              return 1
            fi
          fi
        fi
      fi
      if [ "${replacement_checks}" -ge 200 ]; then
        echo "error: live competing promoter did not release the primary lock; preserving recovery evidence" >&2
        return 1
      fi
      sleep 0.05
    done
    PROMOTION_LOCK_HELD=1
    if ! recovery_guard_owned_by_current_run; then
      PRESERVE_RECOVERY_GUARD=1
      echo "error: promotion recovery guard ownership changed after primary replacement; preserving recovery evidence" >&2
      return 1
    fi
    PRESERVE_RECOVERY_GUARD=0
    release_recovery_guard
    stale_candidate="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${lock_run_id}"
    stale_backup="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${lock_run_id}"
    if ! recover_transaction_paths "${stale_candidate}" "${stale_backup}" \
        "stale promotion"; then
      # The replacement primary already names the failed run, so a later
      # promoter retries the same preserved evidence.
      return 1
    fi
    rm -f "${PROMOTION_ROOT}/promotion-owner.${lock_run_id}"
    printf 'pid=%s\nrun_id=%s\nstarted=%s\n' \
      "$$" "${RUN_ID}" "${replacement_started}" > "${OWNER_MARKER}"
    PRESERVE_PROMOTION_LOCK=0
    return 0
  done
}

if ! acquire_promotion_lock; then
  echo "error: could not acquire the local promotion lock" >&2
  exit 1
fi

# Recover transaction paths from builds predating per-run ownership while the
# new repository-local lock excludes every other promoter.
if ! recover_transaction_paths "${LEGACY_CANDIDATE_APP_DIR}" \
    "${LEGACY_BACKUP_APP_DIR}" "legacy promotion"; then
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
release_promotion_lock

LOCAL_BINARY="${LOCAL_APP_DIR}/Contents/MacOS/${APP_NAME}"
SIZE="$(du -h "${LOCAL_BINARY}" | cut -f1 | tr -d ' ')"
echo "Binary: ${LOCAL_BINARY} (${SIZE})"
echo "Build succeeded: ${LOCAL_APP_DIR}"

if [ "${RUN}" -eq 1 ]; then
  open "${LOCAL_APP_DIR}"
  echo "Launched ${APP_NAME}."
fi
