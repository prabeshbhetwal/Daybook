#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_DIR}"

APP_NAME="FocusContinuity"
PROMOTION_ROOT="${PROJECT_DIR}/.build"
LOCK_FILE="${PROMOTION_ROOT}/promotion.lock"
RECOVERY_GUARD="${PROMOTION_ROOT}/promotion-recovery.lock"
LIVE_RUN_ID="harness-live-$$"
STALE_RUN_ID="harness-stale-$$"
DUAL_STALE_RUN_ID="harness-dual-stale-$$"
SIGNAL_STALE_RUN_ID="harness-signal-stale-$$"
LIVE_OWNER="${PROMOTION_ROOT}/promotion-owner.${LIVE_RUN_ID}"
STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${STALE_RUN_ID}"
DUAL_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${DUAL_STALE_RUN_ID}"
SIGNAL_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${SIGNAL_STALE_RUN_ID}"
LIVE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${LIVE_RUN_ID}"
LIVE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${LIVE_RUN_ID}"
STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${STALE_RUN_ID}"
STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${STALE_RUN_ID}"
DUAL_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${DUAL_STALE_RUN_ID}"
DUAL_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${DUAL_STALE_RUN_ID}"
SIGNAL_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${SIGNAL_STALE_RUN_ID}"
SIGNAL_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${SIGNAL_STALE_RUN_ID}"
HARNESS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focuscontinuity-concurrency.XXXXXX")"
HOLDER_PID=""
FIRST_RECOVERER_PID=""
SECOND_RECOVERER_PID=""
SIGNAL_RECOVERER_PID=""

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

wait_for_file() {
  awaited_file="$1"
  timeout_seconds="$2"
  deadline=$((SECONDS + timeout_seconds))
  while [ ! -e "${awaited_file}" ]; do
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      return 1
    fi
    sleep 0.05
  done
}

wait_for_file_or_process_exit() {
  awaited_file="$1"
  process_id="$2"
  timeout_seconds="$3"
  deadline=$((SECONDS + timeout_seconds))
  while [ ! -e "${awaited_file}" ]; do
    if ! kill -0 "${process_id}" 2>/dev/null; then
      return 1
    fi
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      return 2
    fi
    sleep 0.05
  done
}

cleanup() {
  cleanup_status=$?
  trap - EXIT INT TERM HUP
  if [ -n "${HOLDER_PID}" ]; then
    kill "${HOLDER_PID}" 2>/dev/null || true
    wait "${HOLDER_PID}" 2>/dev/null || true
  fi
  for wrapper_pid_file in \
      "${HARNESS_ROOT}/first-codesign-wrapper.pid" \
      "${HARNESS_ROOT}/second-rm-wrapper.pid" \
      "${HARNESS_ROOT}/signal-codesign-wrapper.pid"; do
    if [ -f "${wrapper_pid_file}" ]; then
      kill "$(<"${wrapper_pid_file}")" 2>/dev/null || true
    fi
  done
  for recoverer_pid in \
      "${FIRST_RECOVERER_PID}" "${SECOND_RECOVERER_PID}" "${SIGNAL_RECOVERER_PID}"; do
    if [ -n "${recoverer_pid}" ]; then
      kill "${recoverer_pid}" 2>/dev/null || true
    fi
  done
  for recoverer_pid in \
      "${FIRST_RECOVERER_PID}" "${SECOND_RECOVERER_PID}" "${SIGNAL_RECOVERER_PID}"; do
    if [ -n "${recoverer_pid}" ]; then
      wait "${recoverer_pid}" 2>/dev/null || true
    fi
  done
  if [ -f "${LOCK_FILE}" ] && grep -Eq \
      "^run_id=(${LIVE_RUN_ID}|${STALE_RUN_ID}|${DUAL_STALE_RUN_ID}|${SIGNAL_STALE_RUN_ID})$" \
      "${LOCK_FILE}"; then
    rm -f "${LOCK_FILE}"
  fi
  for recovery_path in \
      "${SIGNAL_STALE_BACKUP}" "${SIGNAL_STALE_CANDIDATE}" \
      "${DUAL_STALE_BACKUP}" "${DUAL_STALE_CANDIDATE}" \
      "${STALE_BACKUP}" "${STALE_CANDIDATE}"; do
    if [ ! -e "${APP_NAME}.app" ] && [ -e "${recovery_path}" ] \
        && codesign --verify "${recovery_path}" 2>/dev/null; then
      mv "${recovery_path}" "${APP_NAME}.app"
    fi
  done
  rm -f \
    "${LIVE_OWNER}" "${STALE_OWNER}" "${DUAL_STALE_OWNER}" "${SIGNAL_STALE_OWNER}"
  for owner_marker in "${PROMOTION_ROOT}"/promotion-owner.*; do
    if [ -f "${owner_marker}" ] && grep -Eq \
        "^run_id=(${LIVE_RUN_ID}|${STALE_RUN_ID}|${DUAL_STALE_RUN_ID}|${SIGNAL_STALE_RUN_ID})$" \
        "${owner_marker}"; then
      rm -f "${owner_marker}"
    fi
  done
  rm -rf "${LIVE_CANDIDATE}" "${LIVE_BACKUP}"
  rm -rf "${STALE_CANDIDATE}" "${STALE_BACKUP}"
  rm -rf "${DUAL_STALE_CANDIDATE}" "${DUAL_STALE_BACKUP}"
  rm -rf "${SIGNAL_STALE_CANDIDATE}" "${SIGNAL_STALE_BACKUP}"
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
test ! -e "${RECOVERY_GUARD}" || fail "a promotion recovery guard already exists"

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

# Two stale observers must not both be admitted to replace the primary lock.
# The wrappers execute the real commands but impose this exact interleaving:
# both observe the stale owner; the first links its live primary; only then may
# the second attempt its unlink. Current broken code performs that unlink.
WRAPPER_DIR="${HARNESS_ROOT}/wrappers"
mkdir -p "${WRAPPER_DIR}"
cat > "${WRAPPER_DIR}/rm" <<'WRAPPER'
#!/bin/bash
set -eu
is_primary_lock=0
for target in "$@"; do
  if [ "${target}" = "${HARNESS_LOCK_FILE}" ]; then
    is_primary_lock=1
  fi
done
if [ "${is_primary_lock}" -eq 1 ] && [ -n "${HARNESS_RECOVERER:-}" ]; then
  : > "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-before-lock-remove"
  while [ ! -e "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-release-lock-remove" ]; do
    sleep 0.05
  done
  if [ "${HARNESS_RECOVERER}" = "second" ] && [ -f "${HARNESS_LOCK_FILE}" ]; then
    current_run_id="$(sed -n 's/^run_id=//p' "${HARNESS_LOCK_FILE}" | head -n 1)"
    if [ "${current_run_id}" != "${HARNESS_STALE_RUN_ID}" ]; then
      printf '%s\n' "$$" > "${HARNESS_CONTROL_ROOT}/second-rm-wrapper.pid"
      /bin/rm "$@"
      : > "${HARNESS_CONTROL_ROOT}/live-primary-was-removed"
      while [ ! -e "${HARNESS_CONTROL_ROOT}/release-second-after-breach" ]; do
        sleep 0.05
      done
      exit 0
    fi
  fi
fi
exec /bin/rm "$@"
WRAPPER
cat > "${WRAPPER_DIR}/codesign" <<'WRAPPER'
#!/bin/bash
set -eu
for target in "$@"; do
  if [ "${HARNESS_RECOVERER:-}" = "signal" ] \
      && [ "${target}" = "${HARNESS_SIGNAL_BACKUP}" ]; then
    printf '%s\n' "$$" > "${HARNESS_CONTROL_ROOT}/signal-codesign-wrapper.pid"
    : > "${HARNESS_CONTROL_ROOT}/signal-live-primary-linked"
    while [ ! -e "${HARNESS_CONTROL_ROOT}/interrupt-signal-recovery" ]; do
      sleep 0.05
    done
    kill -TERM "${PPID}"
    exit 143
  fi
  if [ "${HARNESS_RECOVERER:-}" = "first" ] \
      && [ "${target}" = "${HARNESS_STALE_BACKUP}" ]; then
    printf '%s\n' "$$" > "${HARNESS_CONTROL_ROOT}/first-codesign-wrapper.pid"
    : > "${HARNESS_CONTROL_ROOT}/first-live-primary-linked"
    while [ ! -e "${HARNESS_CONTROL_ROOT}/first-release-recovery" ]; do
      sleep 0.05
    done
    break
  fi
done
exec /usr/bin/codesign "$@"
WRAPPER
chmod +x "${WRAPPER_DIR}/rm" "${WRAPPER_DIR}/codesign"

mv "${APP_NAME}.app" "${DUAL_STALE_BACKUP}"
cp -R "${DUAL_STALE_BACKUP}" "${DUAL_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${DUAL_STALE_RUN_ID}" > "${DUAL_STALE_OWNER}"
ln "${DUAL_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=first \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_STALE_RUN_ID="${DUAL_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${DUAL_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/first-recoverer.log" 2>&1 &
FIRST_RECOVERER_PID=$!
wait_for_file "${HARNESS_ROOT}/first-before-lock-remove" 120 \
  || fail "the first stale recoverer did not reach the controlled unlink"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=second \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_STALE_RUN_ID="${DUAL_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${DUAL_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/second-recoverer.log" 2>&1 &
SECOND_RECOVERER_PID=$!

if wait_for_file_or_process_exit \
    "${HARNESS_ROOT}/second-before-lock-remove" "${SECOND_RECOVERER_PID}" 120; then
  : > "${HARNESS_ROOT}/first-release-lock-remove"
  wait_for_file "${HARNESS_ROOT}/first-live-primary-linked" 30 \
    || fail "the first stale recoverer did not link its live primary lock"
  : > "${HARNESS_ROOT}/second-release-lock-remove"
  wait_for_file "${HARNESS_ROOT}/live-primary-was-removed" 30 \
    || fail "the controlled second unlink did not execute"
  test ! -e "${HARNESS_ROOT}/live-primary-was-removed" \
    || fail "a second stale recoverer removed the first recoverer's live primary lock"
else
  second_wait_status=$?
  test "${second_wait_status}" -eq 1 \
    || fail "timed out waiting for the second stale recoverer"
  test -f "${LOCK_FILE}" \
    || fail "the rejected stale recoverer removed the observed primary lock"
  grep -F "run_id=${DUAL_STALE_RUN_ID}" "${LOCK_FILE}" >/dev/null \
    || fail "the rejected stale recoverer changed the observed primary owner"
  test -f "${RECOVERY_GUARD}/owner" \
    || fail "the rejected stale recoverer removed the admitted process's guard"
  grep -F "pid=${FIRST_RECOVERER_PID}" "${RECOVERY_GUARD}/owner" >/dev/null \
    || fail "the rejected stale recoverer changed recovery guard ownership"
  test -e "${DUAL_STALE_BACKUP}" -a -e "${DUAL_STALE_CANDIDATE}" \
    || fail "the rejected stale recoverer discarded transaction evidence"
  : > "${HARNESS_ROOT}/first-release-lock-remove"
  wait_for_file "${HARNESS_ROOT}/first-live-primary-linked" 30 \
    || fail "the admitted stale recoverer did not link its live primary lock"
  : > "${HARNESS_ROOT}/first-release-recovery"
fi

set +e
wait "${FIRST_RECOVERER_PID}"
FIRST_STATUS=$?
FIRST_RECOVERER_PID=""
wait "${SECOND_RECOVERER_PID}"
SECOND_STATUS=$?
SECOND_RECOVERER_PID=""
set -e
test "${FIRST_STATUS}" -eq 0 -o "${SECOND_STATUS}" -eq 0 \
  || fail "neither stale recoverer completed"
test ! -e "${LOCK_FILE}" || fail "stale recovery left the primary lock behind"
test ! -e "${RECOVERY_GUARD}" || fail "stale recovery left its guard behind"
codesign --verify "${APP_NAME}.app" \
  || fail "concurrent stale recovery left an invalid local app"
test "$(find "${PROMOTION_ROOT}" -maxdepth 1 \
  \( -name '*.candidate.*' -o -name '*.backup.*' \) | wc -l | tr -d ' ')" = "0" \
  || fail "concurrent stale recovery left transaction debris"

# A signal after primary replacement but before transaction-path recovery must
# leave the old run discoverable. The next ordinary build has no harness hint;
# it can recover the evidence only if the surviving primary names that run.
mv "${APP_NAME}.app" "${SIGNAL_STALE_BACKUP}"
cp -R "${SIGNAL_STALE_BACKUP}" "${SIGNAL_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${SIGNAL_STALE_RUN_ID}" > "${SIGNAL_STALE_OWNER}"
ln "${SIGNAL_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=signal \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_STALE_RUN_ID="${SIGNAL_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${SIGNAL_STALE_BACKUP}" \
HARNESS_SIGNAL_BACKUP="${SIGNAL_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/signal-recoverer.log" 2>&1 &
SIGNAL_RECOVERER_PID=$!
wait_for_file "${HARNESS_ROOT}/signal-before-lock-remove" 120 \
  || fail "the signal stale recoverer did not reach the controlled unlink"
: > "${HARNESS_ROOT}/signal-release-lock-remove"
wait_for_file "${HARNESS_ROOT}/signal-live-primary-linked" 30 \
  || fail "the signal stale recoverer did not link its replacement primary"
: > "${HARNESS_ROOT}/interrupt-signal-recovery"
set +e
wait "${SIGNAL_RECOVERER_PID}"
SIGNAL_STATUS=$?
SIGNAL_RECOVERER_PID=""
set -e
test "${SIGNAL_STATUS}" -ne 0 \
  || fail "the interrupted stale recoverer unexpectedly completed"
test -f "${LOCK_FILE}" \
  || fail "signal cleanup removed the primary that identifies rollback evidence"
grep -F "run_id=${SIGNAL_STALE_RUN_ID}" "${LOCK_FILE}" >/dev/null \
  || fail "signal cleanup left rollback evidence under an undiscoverable run id"
test ! -e "${RECOVERY_GUARD}" \
  || fail "signal cleanup left a recovery guard blocking the evidence retry"
test -e "${SIGNAL_STALE_BACKUP}" -a -e "${SIGNAL_STALE_CANDIDATE}" \
  || fail "signal cleanup discarded interrupted transaction evidence"

./build.sh > "${HARNESS_ROOT}/signal-retry.log" 2>&1 \
  || fail "an ordinary build could not retry the signal-preserved recovery"
test ! -e "${LOCK_FILE}" || fail "the signal recovery retry left the primary lock"
test ! -e "${SIGNAL_STALE_OWNER}" \
  || fail "the signal recovery retry left the stale ownership marker"
test ! -e "${SIGNAL_STALE_BACKUP}" -a ! -e "${SIGNAL_STALE_CANDIDATE}" \
  || fail "the signal recovery retry left transaction debris"
codesign --verify "${APP_NAME}.app" \
  || fail "the signal recovery retry left an invalid local app"

echo "PASS: live contention, non-promoting --check, dual recovery, and signal-safe retry"
