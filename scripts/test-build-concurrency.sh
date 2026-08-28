#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="FocusContinuity"
PROMOTION_ROOT="${PROJECT_DIR}/.build"
LOCK_FILE="${PROMOTION_ROOT}/promotion.lock"
LIVE_RUN_ID="harness-live-$$"
STALE_RUN_ID="harness-stale-$$"
LIVE_OWNER="${PROMOTION_ROOT}/promotion-owner.${LIVE_RUN_ID}"
STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${STALE_RUN_ID}"
LIVE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${LIVE_RUN_ID}"
LIVE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${LIVE_RUN_ID}"
STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${STALE_RUN_ID}"
STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${STALE_RUN_ID}"
HARNESS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focuscontinuity-concurrency.XXXXXX")"
HOLDER_PID=""

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup() {
  cleanup_status=$?
  trap - EXIT INT TERM HUP
  if [ -n "${HOLDER_PID}" ]; then
    kill "${HOLDER_PID}" 2>/dev/null || true
    wait "${HOLDER_PID}" 2>/dev/null || true
  fi
  if [ -f "${LOCK_FILE}" ] && grep -Eq "^run_id=(${LIVE_RUN_ID}|${STALE_RUN_ID})$" "${LOCK_FILE}"; then
    rm -f "${LOCK_FILE}"
  fi
  if [ ! -e "${APP_NAME}.app" ] && [ -e "${STALE_BACKUP}" ] \
      && codesign --verify "${STALE_BACKUP}" 2>/dev/null; then
    mv "${STALE_BACKUP}" "${APP_NAME}.app"
  elif [ ! -e "${APP_NAME}.app" ] && [ -e "${STALE_CANDIDATE}" ] \
      && codesign --verify "${STALE_CANDIDATE}" 2>/dev/null; then
    mv "${STALE_CANDIDATE}" "${APP_NAME}.app"
  fi
  rm -f "${LIVE_OWNER}" "${STALE_OWNER}"
  rm -rf "${LIVE_CANDIDATE}" "${LIVE_BACKUP}"
  rm -rf "${STALE_CANDIDATE}" "${STALE_BACKUP}"
  rm -rf "${HARNESS_ROOT}"
  exit "${cleanup_status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

test -d "${APP_NAME}.app" || fail "a verified local app is required before the harness"
codesign --verify "${APP_NAME}.app" || fail "the baseline local app is not signed"
mkdir -p "${PROMOTION_ROOT}"
test ! -e "${LOCK_FILE}" || fail "a promotion lock already exists"

# A live process owns the promotion transaction. A competing normal build must
# compile independently, then fail fast without touching this owner's paths or
# the already-promoted local app.
sleep 180 &
HOLDER_PID=$!
mkdir -p "${LIVE_CANDIDATE}" "${LIVE_BACKUP}"
printf 'candidate sentinel\n' > "${LIVE_CANDIDATE}/sentinel"
printf 'backup sentinel\n' > "${LIVE_BACKUP}/sentinel"
printf 'pid=%s\nrun_id=%s\nstarted=%s\n' \
  "${HOLDER_PID}" "${LIVE_RUN_ID}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${LIVE_OWNER}"
ln "${LIVE_OWNER}" "${LOCK_FILE}"

BASELINE_HASH="$(shasum -a 256 "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" | awk '{print $1}')"
set +e
./build.sh > "${HARNESS_ROOT}/competing-build.log" 2>&1
COMPETING_STATUS=$?
set -e
test "${COMPETING_STATUS}" -ne 0 || fail "a competing normal build unexpectedly promoted"
grep -F "promotion lock is held by live process ${HOLDER_PID}" \
  "${HARNESS_ROOT}/competing-build.log" >/dev/null \
  || fail "the competing build did not identify the live owner"
test "$(<"${LIVE_CANDIDATE}/sentinel")" = "candidate sentinel" \
  || fail "the competing build changed the live owner's candidate"
test "$(<"${LIVE_BACKUP}/sentinel")" = "backup sentinel" \
  || fail "the competing build changed the live owner's backup"
test "$(shasum -a 256 "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" | awk '{print $1}')" = \
  "${BASELINE_HASH}" || fail "the competing build changed the local app"

# --check is deliberately outside promotion coordination. It must succeed with
# a live owner and leave every promotion path byte-for-byte untouched.
LOCK_HASH="$(shasum -a 256 "${LOCK_FILE}" | awk '{print $1}')"
./build.sh --check > "${HARNESS_ROOT}/check.log" 2>&1 \
  || fail "--check failed while a live promoter existed"
grep -F "Check succeeded:" "${HARNESS_ROOT}/check.log" >/dev/null \
  || fail "--check did not complete its staged verification"
test "$(shasum -a 256 "${LOCK_FILE}" | awk '{print $1}')" = "${LOCK_HASH}" \
  || fail "--check changed the promotion lock"
test "$(<"${LIVE_CANDIDATE}/sentinel")" = "candidate sentinel" \
  || fail "--check changed the live candidate"
test "$(<"${LIVE_BACKUP}/sentinel")" = "backup sentinel" \
  || fail "--check changed the live backup"
test "$(shasum -a 256 "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" | awk '{print $1}')" = \
  "${BASELINE_HASH}" || fail "--check promoted over the local app"

kill "${HOLDER_PID}" 2>/dev/null || true
wait "${HOLDER_PID}" 2>/dev/null || true
HOLDER_PID=""
rm -f "${LOCK_FILE}" "${LIVE_OWNER}"
rm -rf "${LIVE_CANDIDATE}" "${LIVE_BACKUP}"

# A dead owner is recovered under the replacement lock. This is the dangerous
# interruption point: the prior app has already moved to the per-run backup and
# the candidate has not yet reached the local path.
DEAD_PID=999999
while kill -0 "${DEAD_PID}" 2>/dev/null; do DEAD_PID=$((DEAD_PID + 1)); done
mv "${APP_NAME}.app" "${STALE_BACKUP}"
cp -R "${STALE_BACKUP}" "${STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${STALE_RUN_ID}" > "${STALE_OWNER}"
ln "${STALE_OWNER}" "${LOCK_FILE}"

./build.sh > "${HARNESS_ROOT}/stale-build.log" 2>&1 \
  || fail "a normal build could not recover the stale promotion lock"
grep -F "Recovering stale promotion lock owned by process ${DEAD_PID}" \
  "${HARNESS_ROOT}/stale-build.log" >/dev/null \
  || fail "stale-lock recovery was not diagnosed"
grep -F "Recovering missing local app from ${STALE_BACKUP}." \
  "${HARNESS_ROOT}/stale-build.log" >/dev/null \
  || fail "the stale rollback backup was not restored before promotion"
test ! -e "${LOCK_FILE}" || fail "the successful build left the lock behind"
test ! -e "${STALE_OWNER}" || fail "the stale ownership marker survived recovery"
test ! -e "${STALE_CANDIDATE}" || fail "the stale candidate survived recovery"
test ! -e "${STALE_BACKUP}" || fail "the stale backup survived recovery"
codesign --verify "${APP_NAME}.app" || fail "the recovered promotion is not signed"

echo "PASS: live promotion contention, non-promoting --check and stale-lock recovery"
