#!/usr/bin/env bash
#==============================================================================
# tests/t12_buildvisibility.sh - OL7 build-log visibility (layer L1/L2,
#                                 structural + behavioural)
#
# Guards the OL7 build-log visibility work (handoff B.1.5 feedback (4)):
#   C  install-ena-driver.sh emits greppable [ena-driver][stage] breadcrumbs at
#      the phase boundaries (esp. dkms add/build/install -- the long quiet step).
#   D  record_make_log() preserves the DKMS make.log to a stable in-image path
#      on a successful build (guest output is swallowed by virt-customize on
#      success), invoked on the DKMS success path.
#   B  the wrapper records the latest LIVE orchestrator line to BUILD_STAGE_FILE
#      (in log_external) and the Phase-5 heartbeat shows it as "stage: ...".
#   A  the heartbeat assembles each tick into one string and emits a single
#      log_progress write.
#   +  HEARTBEAT_INTERVAL_SEC default is 10s (was 20s).
#
# Host-runnable and self-contained; the real OL7 build/boot is the build-host
# E2E (B-T7/B-T8). Presence checks grep the FILE directly (not a cached "$(cat)"
# piped to grep -q): on a large file grep -q exits on first match before printf
# finishes writing, and `set -o pipefail` would then surface the writer's
# SIGPIPE as a spurious failure.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
WRAP="${PROJ}/build-ol-aws-ami.sh"
INST="${PROJ}/install-ena-driver.sh"

# grep the file directly; see header note on the printf|grep -q + pipefail race.
assert_in() {      # FILE EXTENDED_REGEX MSG
  if grep -Eq -- "$2" "$1"; then t_pass "$3"
  else t_fail "$3 (no match for /$2/ in $(basename "$1"))"; fi
}
assert_not_in() {  # FILE EXTENDED_REGEX MSG
  if grep -Eq -- "$2" "$1"; then t_fail "$3 (unexpected match for /$2/ in $(basename "$1"))"
  else t_pass "$3"; fi
}

# ---- C: in-guest stage breadcrumbs (installer) -----------------------------
assert_in "${INST}" '^stage\(\) \{' \
  "buildvis: stage() breadcrumb helper defined in installer"
assert_in "${INST}" 'stage "dkms build for' \
  "buildvis: [stage] breadcrumb brackets the long dkms build step"
assert_in "${INST}" 'stage "dkms add' \
  "buildvis: [stage] breadcrumb at dkms add"
assert_in "${INST}" 'stage "dkms install for' \
  "buildvis: [stage] breadcrumb at dkms install"
assert_in "${INST}" 'stage "downloading amzn-drivers' \
  "buildvis: [stage] breadcrumb at source download"

# ---- D: success-path make.log preservation (installer) ---------------------
assert_in "${INST}" '^record_make_log\(\) \{' \
  "buildvis: record_make_log() defined in installer"
assert_in "${INST}" '/var/log/ol-aws-ami-builder-ena-make\.log' \
  "buildvis: record_make_log targets the stable in-image make.log path"
assert_in "${INST}" '^[[:space:]]*record_make_log[[:space:]]*$' \
  "buildvis: record_make_log invoked on the DKMS success path"

# ---- B: live stage plumbing (wrapper) --------------------------------------
assert_in "${WRAP}" 'BUILD_STAGE_FILE="\$\{WORKSPACE\}/\.build-stage"' \
  "buildvis: BUILD_STAGE_FILE defined under WORKSPACE"
assert_in "${WRAP}" '> "\$\{BUILD_STAGE_FILE\}"' \
  "buildvis: log_external writes the latest orchestrator line to BUILD_STAGE_FILE"
assert_in "${WRAP}" 'tail -n 1 "\$\{BUILD_STAGE_FILE\}"' \
  "buildvis: heartbeat reads the latest stage from BUILD_STAGE_FILE"
assert_in "${WRAP}" 'stage: \$\{stage\}|\| stage: ' \
  "buildvis: heartbeat appends a 'stage:' field"
assert_in "${WRAP}" 'rm -f "\$\{BUILD_STAGE_FILE\}"' \
  "buildvis: BUILD_STAGE_FILE is cleaned up after the build"

# ---- A: single atomic heartbeat write (wrapper) ----------------------------
assert_in "${WRAP}" 'log_progress "\$\{msg\}"' \
  "buildvis: heartbeat emits one assembled string via a single log_progress write"

# ---- interval default 20 -> 10 (wrapper) -----------------------------------
assert_in "${WRAP}" 'HEARTBEAT_INTERVAL_SEC:=10' \
  "buildvis: HEARTBEAT_INTERVAL_SEC default is 10s"
assert_not_in "${WRAP}" 'HEARTBEAT_INTERVAL_SEC:=20' \
  "buildvis: old 20s default no longer present"

# ---- behavioural: log_external records the LATEST line to BUILD_STAGE_FILE --
# Run in a subshell so the wrapper's own `set -euo pipefail` (applied on source)
# does not leak into this tier's shell.
probe="$(
  bvf="$(mktemp)"
  (
    export BUILD_STAGE_FILE="${bvf}"
    # shellcheck disable=SC1090
    source "${WRAP}" >/dev/null 2>&1 || true
    printf '%s\n' "first orchestrator line" "customizing image (virt-customize)" \
      | log_external "build-image.sh" >/dev/null 2>&1
  )
  tail -n 1 "${bvf}" 2>/dev/null
  rm -f "${bvf}"
)"
assert_match "${probe}" '\[build-image.sh\] customizing image \(virt-customize\)' \
  "buildvis: log_external records the latest line (with source tag) to BUILD_STAGE_FILE"

t_done
