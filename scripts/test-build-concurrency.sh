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
GAP_STALE_RUN_ID="harness-gap-stale-$$"
CLEANUP_STALE_RUN_ID="harness-cleanup-stale-$$"
RETRY_STALE_RUN_ID="harness-retry-stale-$$"
DEAD_STALE_RUN_ID="harness-dead-stale-$$"
SYMLINK_STALE_RUN_ID="harness-symlink-stale-$$"
LIVE_OWNER="${PROMOTION_ROOT}/promotion-owner.${LIVE_RUN_ID}"
STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${STALE_RUN_ID}"
DUAL_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${DUAL_STALE_RUN_ID}"
SIGNAL_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${SIGNAL_STALE_RUN_ID}"
GAP_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${GAP_STALE_RUN_ID}"
CLEANUP_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${CLEANUP_STALE_RUN_ID}"
RETRY_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${RETRY_STALE_RUN_ID}"
DEAD_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${DEAD_STALE_RUN_ID}"
SYMLINK_STALE_OWNER="${PROMOTION_ROOT}/promotion-owner.${SYMLINK_STALE_RUN_ID}"
LIVE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${LIVE_RUN_ID}"
LIVE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${LIVE_RUN_ID}"
STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${STALE_RUN_ID}"
STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${STALE_RUN_ID}"
DUAL_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${DUAL_STALE_RUN_ID}"
DUAL_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${DUAL_STALE_RUN_ID}"
SIGNAL_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${SIGNAL_STALE_RUN_ID}"
SIGNAL_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${SIGNAL_STALE_RUN_ID}"
GAP_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${GAP_STALE_RUN_ID}"
GAP_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${GAP_STALE_RUN_ID}"
CLEANUP_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${CLEANUP_STALE_RUN_ID}"
CLEANUP_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${CLEANUP_STALE_RUN_ID}"
RETRY_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${RETRY_STALE_RUN_ID}"
RETRY_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${RETRY_STALE_RUN_ID}"
DEAD_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${DEAD_STALE_RUN_ID}"
DEAD_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${DEAD_STALE_RUN_ID}"
SYMLINK_STALE_CANDIDATE="${PROMOTION_ROOT}/${APP_NAME}.app.candidate.${SYMLINK_STALE_RUN_ID}"
SYMLINK_STALE_BACKUP="${PROMOTION_ROOT}/${APP_NAME}.app.backup.${SYMLINK_STALE_RUN_ID}"
CLEANUP_PID_RECORD="${PROMOTION_ROOT}/harness-cleanup-probe.pid"
CLEANUP_RUN_RECORD="${PROMOTION_ROOT}/harness-cleanup-probe.run-id"
HARNESS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focuscontinuity-concurrency.XXXXXX")"
HOLDER_PID=""
FIRST_RECOVERER_PID=""
SECOND_RECOVERER_PID=""
SIGNAL_RECOVERER_PID=""
GAP_RECOVERER_PID=""
CLEANUP_RECOVERER_PID=""
PRECHECK_CONTENDER_PID=""
RETRY_RECOVERER_PID=""
DEAD_CONTENDER_PID=""
DEAD_RECOVERER_PID=""
SYMLINK_RECOVERER_PID=""
RED_FAILURES=0

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
  tracked_guard_pid=""
  tracked_guard_run_id=""
  if [ -f "${RECOVERY_GUARD}/owner" ]; then
    observed_guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
    observed_guard_run_id="$(sed -n 's/^run_id=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
    case "${observed_guard_pid}" in
      ""|*[!0-9]*) ;;
      *)
        case "${observed_guard_run_id}" in
          ""|*[!A-Za-z0-9._-]*) ;;
          *)
            for recoverer_pid in \
                "${FIRST_RECOVERER_PID}" "${SECOND_RECOVERER_PID}" \
                "${SIGNAL_RECOVERER_PID}" "${GAP_RECOVERER_PID}" \
                "${CLEANUP_RECOVERER_PID}" "${PRECHECK_CONTENDER_PID}" \
                "${RETRY_RECOVERER_PID}" "${DEAD_CONTENDER_PID}" \
                "${DEAD_RECOVERER_PID}" "${SYMLINK_RECOVERER_PID}"; do
              if [ -n "${recoverer_pid}" ] \
                  && [ "${observed_guard_pid}" = "${recoverer_pid}" ]; then
                tracked_guard_pid="${observed_guard_pid}"
                tracked_guard_run_id="${observed_guard_run_id}"
              fi
            done
            ;;
        esac
        ;;
    esac
  fi
  if [ -n "${HOLDER_PID}" ]; then
    kill "${HOLDER_PID}" 2>/dev/null || true
    wait "${HOLDER_PID}" 2>/dev/null || true
  fi
  for wrapper_pid_file in \
      "${HARNESS_ROOT}/first-codesign-wrapper.pid" \
      "${HARNESS_ROOT}/second-rm-wrapper.pid" \
      "${HARNESS_ROOT}/signal-codesign-wrapper.pid" \
      "${HARNESS_ROOT}/gap-rm-wrapper.pid" \
      "${HARNESS_ROOT}/cleanup-rm-wrapper.pid" \
      "${HARNESS_ROOT}/retry-rm-wrapper.pid" \
      "${HARNESS_ROOT}/prechecked-ln-wrapper.pid" \
      "${HARNESS_ROOT}/dead-prechecked-ln-wrapper.pid" \
      "${HARNESS_ROOT}/dead-retry-rm-wrapper.pid"; do
    if [ -f "${wrapper_pid_file}" ]; then
      kill "$(<"${wrapper_pid_file}")" 2>/dev/null || true
    fi
  done
  for recoverer_pid in \
      "${FIRST_RECOVERER_PID}" "${SECOND_RECOVERER_PID}" "${SIGNAL_RECOVERER_PID}" \
      "${GAP_RECOVERER_PID}" "${CLEANUP_RECOVERER_PID}" \
      "${PRECHECK_CONTENDER_PID}" "${RETRY_RECOVERER_PID}" \
      "${DEAD_CONTENDER_PID}" "${DEAD_RECOVERER_PID}" \
      "${SYMLINK_RECOVERER_PID}"; do
    if [ -n "${recoverer_pid}" ]; then
      kill "${recoverer_pid}" 2>/dev/null || true
    fi
  done
  for recoverer_pid in \
      "${FIRST_RECOVERER_PID}" "${SECOND_RECOVERER_PID}" "${SIGNAL_RECOVERER_PID}" \
      "${GAP_RECOVERER_PID}" "${CLEANUP_RECOVERER_PID}" \
      "${PRECHECK_CONTENDER_PID}" "${RETRY_RECOVERER_PID}" \
      "${DEAD_CONTENDER_PID}" "${DEAD_RECOVERER_PID}" \
      "${SYMLINK_RECOVERER_PID}"; do
    if [ -n "${recoverer_pid}" ]; then
      wait "${recoverer_pid}" 2>/dev/null || true
    fi
  done
  if [ -n "${tracked_guard_pid}" ] \
      && ! kill -0 "${tracked_guard_pid}" 2>/dev/null \
      && [ -f "${RECOVERY_GUARD}/owner" ]; then
    final_guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
    final_guard_run_id="$(sed -n 's/^run_id=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
    if [ "${final_guard_pid}" = "${tracked_guard_pid}" ] \
        && [ "${final_guard_run_id}" = "${tracked_guard_run_id}" ]; then
      rm -f "${RECOVERY_GUARD}/owner"
      if ! rmdir "${RECOVERY_GUARD}" 2>/dev/null; then
        printf 'pid=%s\nrun_id=%s\n' \
          "${tracked_guard_pid}" "${tracked_guard_run_id}" \
          > "${RECOVERY_GUARD}/owner" || true
        cleanup_status=1
      fi
    fi
  fi
  if [ -f "${LOCK_FILE}" ] && grep -Eq \
      "^run_id=(${LIVE_RUN_ID}|${STALE_RUN_ID}|${DUAL_STALE_RUN_ID}|${SIGNAL_STALE_RUN_ID}|${GAP_STALE_RUN_ID}|${CLEANUP_STALE_RUN_ID}|${RETRY_STALE_RUN_ID}|${DEAD_STALE_RUN_ID}|${SYMLINK_STALE_RUN_ID})$" \
      "${LOCK_FILE}"; then
    rm -f "${LOCK_FILE}"
  fi
  for recovery_path in \
      "${SYMLINK_STALE_BACKUP}" "${SYMLINK_STALE_CANDIDATE}" \
      "${DEAD_STALE_BACKUP}" "${DEAD_STALE_CANDIDATE}" \
      "${RETRY_STALE_BACKUP}" "${RETRY_STALE_CANDIDATE}" \
      "${CLEANUP_STALE_BACKUP}" "${CLEANUP_STALE_CANDIDATE}" \
      "${GAP_STALE_BACKUP}" "${GAP_STALE_CANDIDATE}" \
      "${SIGNAL_STALE_BACKUP}" "${SIGNAL_STALE_CANDIDATE}" \
      "${DUAL_STALE_BACKUP}" "${DUAL_STALE_CANDIDATE}" \
      "${STALE_BACKUP}" "${STALE_CANDIDATE}"; do
    if [ ! -e "${APP_NAME}.app" ] && [ -e "${recovery_path}" ] \
        && codesign --verify "${recovery_path}" 2>/dev/null; then
      mv "${recovery_path}" "${APP_NAME}.app"
    fi
  done
  rm -f \
    "${LIVE_OWNER}" "${STALE_OWNER}" "${DUAL_STALE_OWNER}" "${SIGNAL_STALE_OWNER}" \
    "${GAP_STALE_OWNER}" "${CLEANUP_STALE_OWNER}" "${RETRY_STALE_OWNER}"
  rm -f "${DEAD_STALE_OWNER}"
  rm -f "${SYMLINK_STALE_OWNER}"
  for owner_marker in "${PROMOTION_ROOT}"/promotion-owner.*; do
    if [ -f "${owner_marker}" ] && grep -Eq \
        "^run_id=(${LIVE_RUN_ID}|${STALE_RUN_ID}|${DUAL_STALE_RUN_ID}|${SIGNAL_STALE_RUN_ID}|${GAP_STALE_RUN_ID}|${CLEANUP_STALE_RUN_ID}|${RETRY_STALE_RUN_ID}|${DEAD_STALE_RUN_ID}|${SYMLINK_STALE_RUN_ID})$" \
        "${owner_marker}"; then
      rm -f "${owner_marker}"
    fi
  done
  rm -rf "${LIVE_CANDIDATE}" "${LIVE_BACKUP}"
  rm -rf "${STALE_CANDIDATE}" "${STALE_BACKUP}"
  rm -rf "${DUAL_STALE_CANDIDATE}" "${DUAL_STALE_BACKUP}"
  rm -rf "${SIGNAL_STALE_CANDIDATE}" "${SIGNAL_STALE_BACKUP}"
  rm -rf "${GAP_STALE_CANDIDATE}" "${GAP_STALE_BACKUP}"
  rm -rf "${CLEANUP_STALE_CANDIDATE}" "${CLEANUP_STALE_BACKUP}"
  rm -rf "${RETRY_STALE_CANDIDATE}" "${RETRY_STALE_BACKUP}"
  rm -rf "${DEAD_STALE_CANDIDATE}" "${DEAD_STALE_BACKUP}"
  rm -rf "${SYMLINK_STALE_CANDIDATE}" "${SYMLINK_STALE_BACKUP}"
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
if [ "${is_primary_lock}" -eq 1 ] && [ -n "${HARNESS_RECOVERER:-}" ] \
    && [ "${HARNESS_RECOVERER}" != "prechecked" ] \
    && [ "${HARNESS_RECOVERER}" != "dead-prechecked" ] \
    && [ "${HARNESS_RECOVERER}" != "symlink" ] \
    && [ "${HARNESS_RECOVERER}" != "release-symlink" ]; then
  : > "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-before-lock-remove"
  while [ ! -e "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-release-lock-remove" ]; do
    sleep 0.05
  done
  if [ "${HARNESS_RECOVERER}" = "gap" ] \
      || [ "${HARNESS_RECOVERER}" = "cleanup" ] \
      || [ "${HARNESS_RECOVERER}" = "retry" ] \
      || [ "${HARNESS_RECOVERER}" = "dead-retry" ]; then
    printf '%s\n' "$$" \
      > "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-rm-wrapper.pid"
    /bin/rm "$@"
    : > "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-primary-unlinked"
    while [ ! -e "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-release-after-unlink" ]; do
      sleep 0.05
    done
    exit 0
  fi
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
cat > "${WRAPPER_DIR}/ln" <<'WRAPPER'
#!/bin/bash
set -eu
is_primary_lock=0
for target in "$@"; do
  if [ "${target}" = "${HARNESS_LOCK_FILE}" ]; then
    is_primary_lock=1
  fi
done
if [ "${is_primary_lock}" -eq 1 ] \
    && [ "${HARNESS_RECOVERER:-}" = "symlink" ] \
    && [ -e "${HARNESS_RECOVERY_GUARD}" ] \
    && [ ! -e "${HARNESS_LOCK_FILE}" ] \
    && [ ! -L "${HARNESS_LOCK_FILE}" ]; then
  /bin/ln -s "$1" "${HARNESS_LOCK_FILE}"
  printf '%s\n' "$1" > "${HARNESS_CONTROL_ROOT}/symlink-primary-target"
  : > "${HARNESS_CONTROL_ROOT}/symlink-primary-installed"
  exit 1
fi
if [ "${is_primary_lock}" -eq 1 ] \
    && { [ "${HARNESS_RECOVERER:-}" = "prechecked" ] \
      || [ "${HARNESS_RECOVERER:-}" = "dead-prechecked" ]; }; then
  prechecked_prefix="${HARNESS_RECOVERER}"
  : > "${HARNESS_CONTROL_ROOT}/${prechecked_prefix}-before-primary-link"
  while [ ! -e "${HARNESS_CONTROL_ROOT}/${prechecked_prefix}-release-primary-link" ]; do
    sleep 0.05
  done
  if /bin/ln "$@"; then
    printf '%s\n' "$$" \
      > "${HARNESS_CONTROL_ROOT}/${prechecked_prefix}-ln-wrapper.pid"
    : > "${HARNESS_CONTROL_ROOT}/${prechecked_prefix}-primary-linked"
    while [ ! -e "${HARNESS_CONTROL_ROOT}/${prechecked_prefix}-return-from-link" ]; do
      sleep 0.05
    done
    exit 0
  else
    link_status=$?
    exit "${link_status}"
  fi
fi
if [ "${is_primary_lock}" -eq 1 ] \
    && { [ "${HARNESS_RECOVERER:-}" = "retry" ] \
      || [ "${HARNESS_RECOVERER:-}" = "dead-retry" ]; } \
    && [ -e "${HARNESS_RECOVERY_GUARD}" ]; then
  if /bin/ln "$@"; then
    exit 0
  else
    link_status=$?
    : > "${HARNESS_CONTROL_ROOT}/${HARNESS_RECOVERER}-replacement-link-failed"
    exit "${link_status}"
  fi
fi
exec /bin/ln "$@"
WRAPPER
cat > "${WRAPPER_DIR}/stat" <<'WRAPPER'
#!/bin/bash
set -eu
is_primary_lock=0
for target in "$@"; do
  if [ "${target}" = "${HARNESS_LOCK_FILE}" ]; then
    is_primary_lock=1
  fi
done
if [ "${is_primary_lock}" -eq 1 ] \
    && { [ "${HARNESS_RECOVERER:-}" = "retry" ] \
      || [ "${HARNESS_RECOVERER:-}" = "dead-retry" ]; } \
    && [ -e "${HARNESS_RECOVERY_GUARD}" ] \
    && [ -f "${HARNESS_LOCK_FILE}" ]; then
  current_pid="$(sed -n 's/^pid=//p' "${HARNESS_LOCK_FILE}" | head -n 1)"
  if [ "${current_pid}" = "${HARNESS_COMPETING_PID}" ]; then
    stat_output="$(/usr/bin/stat "$@")" || exit $?
    retry_prefix="${HARNESS_RECOVERER}"
    stat_count=0
    if [ -f "${HARNESS_CONTROL_ROOT}/${retry_prefix}-competing-stat-count" ]; then
      stat_count="$(<"${HARNESS_CONTROL_ROOT}/${retry_prefix}-competing-stat-count")"
    fi
    stat_count=$((stat_count + 1))
    printf '%s\n' "${stat_count}" \
      > "${HARNESS_CONTROL_ROOT}/${retry_prefix}-competing-stat-count"
    if [ "${stat_count}" -eq 2 ]; then
      : > "${HARNESS_CONTROL_ROOT}/${retry_prefix}-competing-snapshot-ready"
      while [ ! -e "${HARNESS_CONTROL_ROOT}/${retry_prefix}-release-competing-snapshot" ]; do
        sleep 0.05
      done
    fi
    printf '%s\n' "${stat_output}"
    exit 0
  fi
fi
exec /usr/bin/stat "$@"
WRAPPER
cat > "${WRAPPER_DIR}/codesign" <<'WRAPPER'
#!/bin/bash
set -eu
if [ "${HARNESS_RECOVERER:-}" = "release-symlink" ] \
    && [ -f "${HARNESS_LOCK_FILE}" ] \
    && [ ! -L "${HARNESS_LOCK_FILE}" ]; then
  release_run_id="$(sed -n 's/^run_id=//p' "${HARNESS_LOCK_FILE}" | head -n 1)"
  release_owner="${HARNESS_PROMOTION_ROOT}/promotion-owner.${release_run_id}"
  if [ -f "${release_owner}" ] \
      && [ "${release_owner}" -ef "${HARNESS_LOCK_FILE}" ]; then
    /bin/rm "${HARNESS_LOCK_FILE}"
    /bin/ln -s "${release_owner}" "${HARNESS_LOCK_FILE}"
    printf '%s\n' "${release_owner}" \
      > "${HARNESS_CONTROL_ROOT}/release-symlink-primary-target"
    : > "${HARNESS_CONTROL_ROOT}/release-symlink-primary-installed"
  fi
fi
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
chmod +x \
  "${WRAPPER_DIR}/rm" "${WRAPPER_DIR}/ln" \
  "${WRAPPER_DIR}/stat" "${WRAPPER_DIR}/codesign"

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

# Recovery admission must also cover a promoter that arrives only after the
# stale primary has been unlinked. The admitted process is held inside the real
# rm wrapper after /bin/rm completes but before build.sh can link its replacement.
mv "${APP_NAME}.app" "${GAP_STALE_BACKUP}"
cp -R "${GAP_STALE_BACKUP}" "${GAP_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${GAP_STALE_RUN_ID}" > "${GAP_STALE_OWNER}"
ln "${GAP_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=gap \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_STALE_RUN_ID="${GAP_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${GAP_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/gap-recoverer.log" 2>&1 &
GAP_RECOVERER_PID=$!
wait_for_file "${HARNESS_ROOT}/gap-before-lock-remove" 120 \
  || fail "the gap recoverer did not reach the controlled unlink"
: > "${HARNESS_ROOT}/gap-release-lock-remove"
wait_for_file "${HARNESS_ROOT}/gap-primary-unlinked" 30 \
  || fail "the gap recoverer did not execute the real primary unlink"
test ! -e "${LOCK_FILE}" || fail "the primary path was not empty during the controlled gap"
test -f "${RECOVERY_GUARD}/owner" \
  || fail "the admitted gap recoverer did not retain its recovery guard"

set +e
./build.sh > "${HARNESS_ROOT}/fresh-gap-promoter.log" 2>&1
FRESH_GAP_STATUS=$?
set -e
test -e "${GAP_STALE_BACKUP}" -a -e "${GAP_STALE_CANDIDATE}" \
  || fail "the fresh gap promoter discarded interrupted transaction evidence"
: > "${HARNESS_ROOT}/gap-release-after-unlink"
set +e
wait "${GAP_RECOVERER_PID}"
GAP_STATUS=$?
GAP_RECOVERER_PID=""
set -e
test "${GAP_STATUS}" -eq 0 || fail "the admitted gap recoverer did not complete"
if [ "${FRESH_GAP_STATUS}" -eq 0 ]; then
  echo "FAIL: a fresh promoter acquired the primary during live recovery admission" >&2
  RED_FAILURES=1
else
  grep -F "another process is recovering a stale promotion lock" \
    "${HARNESS_ROOT}/fresh-gap-promoter.log" >/dev/null \
    || fail "the fresh gap promoter did not diagnose recovery admission"
fi
test ! -e "${LOCK_FILE}" -a ! -e "${RECOVERY_GUARD}" \
  || fail "the gap recovery left coordination debris"
test ! -e "${GAP_STALE_BACKUP}" -a ! -e "${GAP_STALE_CANDIDATE}" \
  || fail "the gap recovery left transaction debris"
codesign --verify "${APP_NAME}.app" \
  || fail "the gap recovery left an invalid local app"

# A contender may pass its no-guard check before recovery admission, then link
# only after the admitted recoverer has removed the stale primary. Hold that
# contender inside the real ln, make the recoverer's first replacement collide,
# then let the contender's post-link guard check release its own hard link.
mv "${APP_NAME}.app" "${RETRY_STALE_BACKUP}"
cp -R "${RETRY_STALE_BACKUP}" "${RETRY_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${RETRY_STALE_RUN_ID}" > "${RETRY_STALE_OWNER}"
ln "${RETRY_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=prechecked \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_RECOVERY_GUARD="${RECOVERY_GUARD}" \
  ./build.sh > "${HARNESS_ROOT}/prechecked-contender.log" 2>&1 &
PRECHECK_CONTENDER_PID=$!
wait_for_file "${HARNESS_ROOT}/prechecked-before-primary-link" 120 \
  || fail "the pre-checked contender did not pause before its primary link"
test ! -e "${RECOVERY_GUARD}" \
  || fail "recovery admission existed before the contender's pre-link pause"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=retry \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_RECOVERY_GUARD="${RECOVERY_GUARD}" \
HARNESS_COMPETING_PID="${PRECHECK_CONTENDER_PID}" \
HARNESS_STALE_RUN_ID="${RETRY_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${RETRY_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/retry-recoverer.log" 2>&1 &
RETRY_RECOVERER_PID=$!
wait_for_file "${HARNESS_ROOT}/retry-before-lock-remove" 120 \
  || fail "the admitted retry recoverer did not reach the stale unlink"
: > "${HARNESS_ROOT}/retry-release-lock-remove"
wait_for_file "${HARNESS_ROOT}/retry-primary-unlinked" 30 \
  || fail "the admitted retry recoverer did not remove the stale primary"
: > "${HARNESS_ROOT}/prechecked-release-primary-link"
wait_for_file "${HARNESS_ROOT}/prechecked-primary-linked" 30 \
  || fail "the pre-checked contender did not link during recovery admission"
: > "${HARNESS_ROOT}/retry-release-after-unlink"
wait_for_file "${HARNESS_ROOT}/retry-replacement-link-failed" 30 \
  || fail "the admitted recoverer's first replacement did not collide"
wait_for_file "${HARNESS_ROOT}/retry-competing-snapshot-ready" 30 \
  || fail "the admitted recoverer did not snapshot the transient contender"
: > "${HARNESS_ROOT}/prechecked-return-from-link"

set +e
wait "${PRECHECK_CONTENDER_PID}"
PRECHECK_CONTENDER_STATUS=$?
set -e
test "${PRECHECK_CONTENDER_STATUS}" -ne 0 \
  || fail "the pre-checked contender unexpectedly completed promotion"
test ! -e "${LOCK_FILE}" \
  || fail "the pre-checked contender did not release its own primary inode"
: > "${HARNESS_ROOT}/retry-release-competing-snapshot"
set +e
wait "${RETRY_RECOVERER_PID}"
RETRY_RECOVERER_STATUS=$?
set -e
if [ "${RETRY_RECOVERER_STATUS}" -ne 0 ]; then
  echo "FAIL: guarded recovery did not retry after the transient contender released its primary" >&2
  RED_FAILURES=1
fi

# RED teardown is deliberately narrower than harness cleanup so later cleanup
# probes can still use their wrappers. Remove only the exact dead retry owner.
if [ -e "${RECOVERY_GUARD}" ]; then
  retry_guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
  if [ "${retry_guard_pid}" = "${RETRY_RECOVERER_PID}" ] \
      && ! kill -0 "${retry_guard_pid}" 2>/dev/null; then
    rm -f "${RECOVERY_GUARD}/owner"
    rmdir "${RECOVERY_GUARD}"
  else
    fail "the replacement retry left a live or unknown recovery guard"
  fi
fi
if [ ! -e "${APP_NAME}.app" ] && [ -e "${RETRY_STALE_BACKUP}" ]; then
  mv "${RETRY_STALE_BACKUP}" "${APP_NAME}.app"
fi
rm -f "${RETRY_STALE_OWNER}"
for owner_marker in "${PROMOTION_ROOT}"/promotion-owner.*; do
  if [ -f "${owner_marker}" ] \
      && grep -F "run_id=${RETRY_STALE_RUN_ID}" "${owner_marker}" >/dev/null; then
    rm -f "${owner_marker}"
  fi
done
rm -rf "${RETRY_STALE_CANDIDATE}" "${RETRY_STALE_BACKUP}"
PRECHECK_CONTENDER_PID=""
RETRY_RECOVERER_PID=""
test ! -e "${LOCK_FILE}" -a ! -e "${RECOVERY_GUARD}" \
  || fail "the replacement retry left coordination debris"
codesign --verify "${APP_NAME}.app" \
  || fail "the replacement retry left an invalid local app"

# If the contender dies but leaves the same inode behind, guarded recovery must
# not infer ownership release or remove that dead owner's primary. This is the
# fail-closed counterpart to the disappeared-inode retry above.
mv "${APP_NAME}.app" "${DEAD_STALE_BACKUP}"
cp -R "${DEAD_STALE_BACKUP}" "${DEAD_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${DEAD_STALE_RUN_ID}" > "${DEAD_STALE_OWNER}"
ln "${DEAD_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=dead-prechecked \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_RECOVERY_GUARD="${RECOVERY_GUARD}" \
  ./build.sh > "${HARNESS_ROOT}/dead-prechecked-contender.log" 2>&1 &
DEAD_CONTENDER_PID=$!
wait_for_file "${HARNESS_ROOT}/dead-prechecked-before-primary-link" 120 \
  || fail "the dead-owner contender did not pause before its primary link"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=dead-retry \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_RECOVERY_GUARD="${RECOVERY_GUARD}" \
HARNESS_COMPETING_PID="${DEAD_CONTENDER_PID}" \
HARNESS_STALE_RUN_ID="${DEAD_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${DEAD_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/dead-retry-recoverer.log" 2>&1 &
DEAD_RECOVERER_PID=$!
wait_for_file "${HARNESS_ROOT}/dead-retry-before-lock-remove" 120 \
  || fail "the dead-owner recoverer did not reach the stale unlink"
: > "${HARNESS_ROOT}/dead-retry-release-lock-remove"
wait_for_file "${HARNESS_ROOT}/dead-retry-primary-unlinked" 30 \
  || fail "the dead-owner recoverer did not remove the stale primary"
: > "${HARNESS_ROOT}/dead-prechecked-release-primary-link"
wait_for_file "${HARNESS_ROOT}/dead-prechecked-primary-linked" 30 \
  || fail "the dead-owner contender did not link its primary"
: > "${HARNESS_ROOT}/dead-retry-release-after-unlink"
wait_for_file "${HARNESS_ROOT}/dead-retry-replacement-link-failed" 30 \
  || fail "the dead-owner recoverer's first replacement did not collide"
wait_for_file "${HARNESS_ROOT}/dead-retry-competing-snapshot-ready" 30 \
  || fail "the dead-owner recoverer did not snapshot the competing primary"

kill -KILL "${DEAD_CONTENDER_PID}" 2>/dev/null || true
dead_ln_wrapper_pid="$(<"${HARNESS_ROOT}/dead-prechecked-ln-wrapper.pid")"
kill -KILL "${dead_ln_wrapper_pid}" 2>/dev/null || true
set +e
wait "${DEAD_CONTENDER_PID}"
DEAD_CONTENDER_STATUS=$?
set -e
test "${DEAD_CONTENDER_STATUS}" -ne 0 \
  || fail "the dead-owner contender unexpectedly exited successfully"
test -f "${LOCK_FILE}" \
  || fail "the dead-owner contender did not leave its primary inode"
grep -F "pid=${DEAD_CONTENDER_PID}" "${LOCK_FILE}" >/dev/null \
  || fail "the retained competing primary does not name the dead contender"
dead_contender_run_id="$(sed -n 's/^run_id=//p' "${LOCK_FILE}" | head -n 1)"
: > "${HARNESS_ROOT}/dead-retry-release-competing-snapshot"
set +e
wait "${DEAD_RECOVERER_PID}"
DEAD_RECOVERER_STATUS=$?
set -e
test "${DEAD_RECOVERER_STATUS}" -ne 0 \
  || fail "guarded recovery removed or replaced the dead owner's primary"
grep -F "competing promotion lock owner is not live" \
  "${HARNESS_ROOT}/dead-retry-recoverer.log" >/dev/null \
  || fail "guarded recovery did not diagnose the retained dead-owner inode"

dead_guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
test "${dead_guard_pid}" = "${DEAD_RECOVERER_PID}" \
  || fail "dead-owner recovery left an unknown guard"
test ! -e "${APP_NAME}.app" \
  || fail "dead-owner recovery unexpectedly changed the local app"
rm -f "${RECOVERY_GUARD}/owner"
rmdir "${RECOVERY_GUARD}"
rm -f "${LOCK_FILE}" "${DEAD_STALE_OWNER}"
if [ -e "${DEAD_STALE_BACKUP}" ]; then
  mv "${DEAD_STALE_BACKUP}" "${APP_NAME}.app"
fi
for owner_marker in "${PROMOTION_ROOT}"/promotion-owner.*; do
  if [ -f "${owner_marker}" ] \
      && { grep -F "run_id=${DEAD_STALE_RUN_ID}" "${owner_marker}" >/dev/null \
        || grep -F "run_id=${dead_contender_run_id}" "${owner_marker}" >/dev/null; }; then
    rm -f "${owner_marker}"
  fi
done
rm -rf "${DEAD_STALE_CANDIDATE}" "${DEAD_STALE_BACKUP}"
DEAD_CONTENDER_PID=""
DEAD_RECOVERER_PID=""
codesign --verify "${APP_NAME}.app" \
  || fail "dead-owner regression teardown restored an invalid local app"

# `-ef` follows symlinks. Inject a primary symlink resolving to the admitted
# recoverer's owner marker after its real replacement ln fails; it must not be
# accepted as the recoverer's own hard-linked primary or removed during cleanup.
mv "${APP_NAME}.app" "${SYMLINK_STALE_BACKUP}"
cp -R "${SYMLINK_STALE_BACKUP}" "${SYMLINK_STALE_CANDIDATE}"
printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
  "${DEAD_PID}" "${SYMLINK_STALE_RUN_ID}" > "${SYMLINK_STALE_OWNER}"
ln "${SYMLINK_STALE_OWNER}" "${LOCK_FILE}"

PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=symlink \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_RECOVERY_GUARD="${RECOVERY_GUARD}" \
HARNESS_STALE_RUN_ID="${SYMLINK_STALE_RUN_ID}" \
HARNESS_STALE_BACKUP="${SYMLINK_STALE_BACKUP}" \
  ./build.sh > "${HARNESS_ROOT}/symlink-recoverer.log" 2>&1 &
SYMLINK_RECOVERER_PID=$!
set +e
wait "${SYMLINK_RECOVERER_PID}"
SYMLINK_RECOVERER_STATUS=$?
set -e
test -e "${HARNESS_ROOT}/symlink-primary-installed" \
  || fail "the idempotency regression did not install the primary symlink"
if [ "${SYMLINK_RECOVERER_STATUS}" -eq 0 ] || [ ! -L "${LOCK_FILE}" ]; then
  echo "FAIL: guarded recovery accepted and removed a primary symlink as its own hard link" >&2
  RED_FAILURES=1
fi

if [ -L "${LOCK_FILE}" ]; then
  expected_symlink_target="$(<"${HARNESS_ROOT}/symlink-primary-target")"
  test "$(readlink "${LOCK_FILE}")" = "${expected_symlink_target}" \
    || fail "the fail-closed primary symlink target changed"
  grep -F "competing promotion lock is unverifiable" \
    "${HARNESS_ROOT}/symlink-recoverer.log" >/dev/null \
    || fail "guarded recovery did not diagnose the primary symlink"
  rm -f "${LOCK_FILE}"
fi
if [ -e "${RECOVERY_GUARD}" ]; then
  symlink_guard_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
  if [ "${symlink_guard_pid}" = "${SYMLINK_RECOVERER_PID}" ] \
      && ! kill -0 "${symlink_guard_pid}" 2>/dev/null; then
    rm -f "${RECOVERY_GUARD}/owner"
    rmdir "${RECOVERY_GUARD}"
  else
    fail "symlink regression left a live or unknown recovery guard"
  fi
fi
if [ ! -e "${APP_NAME}.app" ] && [ -e "${SYMLINK_STALE_BACKUP}" ]; then
  mv "${SYMLINK_STALE_BACKUP}" "${APP_NAME}.app"
fi
rm -f "${SYMLINK_STALE_OWNER}"
for owner_marker in "${PROMOTION_ROOT}"/promotion-owner.*; do
  if [ -f "${owner_marker}" ] \
      && grep -F "run_id=${SYMLINK_STALE_RUN_ID}" "${owner_marker}" >/dev/null; then
    rm -f "${owner_marker}"
  fi
done
rm -rf "${SYMLINK_STALE_CANDIDATE}" "${SYMLINK_STALE_BACKUP}"
SYMLINK_RECOVERER_PID=""
codesign --verify "${APP_NAME}.app" \
  || fail "symlink regression teardown restored an invalid local app"

# Audit the ordinary owner-release site separately. Replace its legitimate
# hard link with a symlink after acquisition; release must leave that foreign
# directory entry untouched even though it resolves to the owner's inode.
PATH="${WRAPPER_DIR}:${PATH}" \
HARNESS_RECOVERER=release-symlink \
HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
HARNESS_LOCK_FILE="${LOCK_FILE}" \
HARNESS_PROMOTION_ROOT="${PROMOTION_ROOT}" \
  ./build.sh > "${HARNESS_ROOT}/release-symlink-build.log" 2>&1 \
  || fail "the release-site symlink build did not complete"
test -e "${HARNESS_ROOT}/release-symlink-primary-installed" \
  || fail "the release-site regression did not install its primary symlink"
if [ ! -L "${LOCK_FILE}" ]; then
  echo "FAIL: promotion release removed a primary symlink resolving to its owner" >&2
  RED_FAILURES=1
else
  expected_release_target="$(<"${HARNESS_ROOT}/release-symlink-primary-target")"
  test "$(readlink "${LOCK_FILE}")" = "${expected_release_target}" \
    || fail "promotion release changed the foreign symlink target"
  rm -f "${LOCK_FILE}"
fi
codesign --verify "${APP_NAME}.app" \
  || fail "release-site symlink regression left an invalid local app"

# Exercise this harness's actual EXIT cleanup in a subshell while a tracked
# recoverer is paused after unlink. The parent then observes whether cleanup
# leaked that recoverer's owned guard, and tears down only the proven dead owner.
set +e
(
  trap cleanup EXIT
  mv "${APP_NAME}.app" "${CLEANUP_STALE_BACKUP}"
  cp -R "${CLEANUP_STALE_BACKUP}" "${CLEANUP_STALE_CANDIDATE}"
  printf 'pid=%s\nrun_id=%s\nstarted=2000-01-01T00:00:00Z\n' \
    "${DEAD_PID}" "${CLEANUP_STALE_RUN_ID}" > "${CLEANUP_STALE_OWNER}"
  ln "${CLEANUP_STALE_OWNER}" "${LOCK_FILE}"

  PATH="${WRAPPER_DIR}:${PATH}" \
  HARNESS_RECOVERER=cleanup \
  HARNESS_CONTROL_ROOT="${HARNESS_ROOT}" \
  HARNESS_LOCK_FILE="${LOCK_FILE}" \
  HARNESS_STALE_RUN_ID="${CLEANUP_STALE_RUN_ID}" \
  HARNESS_STALE_BACKUP="${CLEANUP_STALE_BACKUP}" \
    ./build.sh > "${HARNESS_ROOT}/cleanup-recoverer.log" 2>&1 &
  CLEANUP_RECOVERER_PID=$!
  wait_for_file "${HARNESS_ROOT}/cleanup-before-lock-remove" 120 \
    || fail "the cleanup recoverer did not reach the controlled unlink"
  : > "${HARNESS_ROOT}/cleanup-release-lock-remove"
  wait_for_file "${HARNESS_ROOT}/cleanup-primary-unlinked" 30 \
    || fail "the cleanup recoverer did not execute the real primary unlink"
  test -f "${RECOVERY_GUARD}/owner" \
    || fail "the cleanup recoverer did not hold a recovery guard"
  printf '%s\n' "${CLEANUP_RECOVERER_PID}" > "${CLEANUP_PID_RECORD}"
  sed -n 's/^run_id=//p' "${RECOVERY_GUARD}/owner" | head -n 1 \
    > "${CLEANUP_RUN_RECORD}"
  exit 97
)
CLEANUP_PROBE_STATUS=$?
set -e
test "${CLEANUP_PROBE_STATUS}" -eq 97 \
  || fail "the cleanup probe did not exercise the intended failure exit"

CLEANUP_GUARD_LEAKED=0
if [ -e "${RECOVERY_GUARD}" ]; then
  CLEANUP_GUARD_LEAKED=1
  echo "FAIL: harness cleanup leaked a tracked recoverer's recovery guard" >&2
  expected_cleanup_pid="$(<"${CLEANUP_PID_RECORD}")"
  expected_cleanup_run="$(<"${CLEANUP_RUN_RECORD}")"
  actual_cleanup_pid="$(sed -n 's/^pid=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
  actual_cleanup_run="$(sed -n 's/^run_id=//p' "${RECOVERY_GUARD}/owner" | head -n 1)"
  if [ "${actual_cleanup_pid}" = "${expected_cleanup_pid}" ] \
      && [ "${actual_cleanup_run}" = "${expected_cleanup_run}" ] \
      && ! kill -0 "${actual_cleanup_pid}" 2>/dev/null; then
    rm -f "${RECOVERY_GUARD}/owner"
    rmdir "${RECOVERY_GUARD}"
  else
    fail "the cleanup probe encountered an unknown or live recovery guard"
  fi
fi
rm -f "${CLEANUP_PID_RECORD}" "${CLEANUP_RUN_RECORD}"
test -d "${APP_NAME}.app" || fail "cleanup probe did not restore the local app"
codesign --verify "${APP_NAME}.app" || fail "cleanup probe restored an invalid local app"
test ! -e "${LOCK_FILE}" || fail "cleanup probe left the primary lock"
if [ "${CLEANUP_GUARD_LEAKED}" -eq 1 ]; then
  RED_FAILURES=1
fi

# A guard not owned by any tracked harness process must remain byte-identical.
mkdir "${RECOVERY_GUARD}"
printf 'pid=%s\nrun_id=harness-unknown-%s\n' "$$" "$$" \
  > "${RECOVERY_GUARD}/owner"
UNKNOWN_GUARD_HASH="$(shasum -a 256 "${RECOVERY_GUARD}/owner" | awk '{print $1}')"
set +e
(
  trap cleanup EXIT
  exit 96
)
UNKNOWN_GUARD_PROBE_STATUS=$?
set -e
test "${UNKNOWN_GUARD_PROBE_STATUS}" -eq 96 \
  || fail "the unknown-guard cleanup probe did not preserve its exit status"
test -f "${RECOVERY_GUARD}/owner" \
  || fail "harness cleanup removed an unknown recovery guard"
test "$(shasum -a 256 "${RECOVERY_GUARD}/owner" | awk '{print $1}')" = \
  "${UNKNOWN_GUARD_HASH}" || fail "harness cleanup changed an unknown recovery guard"
rm -f "${RECOVERY_GUARD}/owner"
rmdir "${RECOVERY_GUARD}"

test "${RED_FAILURES}" -eq 0 || exit 1

echo "PASS: contention, stale recovery admission, signal retry, and owned cleanup"
