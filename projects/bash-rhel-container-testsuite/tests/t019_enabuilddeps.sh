#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: ENA entitled build-dep installer
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t019_enabuilddeps.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t019_enabuilddeps.sh - L1 unit: ENA entitled build-dep installer
#
# Loads ONLY ensure_build_deps (extracted from install-aws_ena-driver.sh) with
# run_pm/ena_pm/log stubbed, and pins the behaviour that three separate bugs
# regressed:
#   - r22: it must install PLAIN `kernel-devel`, not `kernel-devel-$(uname -r)`
#          (the host-kernel version breaks every cross-major container).
#   - r23: rc must be a plain return (0/1/3) the caller can branch on.
#   - r24: same plain-kernel-devel guarantee, verified explicitly here.
# No podman, no network, no real package manager.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
ENA="${PROJ}/install-aws_ena-driver.sh"

# Load just the function under test.
# shellcheck disable=SC1090
. <(awk '/^ensure_build_deps\(\)/{p=1} p{print} p&&/^\}/{exit}' "${ENA}")

if ! declare -F ensure_build_deps >/dev/null 2>&1; then
  t_fail "could not load ensure_build_deps from install-aws_ena-driver.sh"
  t_done; exit
fi

# --- stubs the function depends on ------------------------------------------
ENA_PM_LOG=""
ENA_BUILD_PLAN="make"
log() { :; }
ena_pm() { printf 'dnf'; }
CALLS=""        # records every run_pm invocation for spying
RP_FAIL=""      # if a run_pm arg string contains this substring, that call fails
run_pm() {
  CALLS="${CALLS}
$*"
  if [ -n "${RP_FAIL}" ]; then
    case "$*" in *"${RP_FAIL}"*) return 1 ;; esac
  fi
  return 0
}
# ENA_PM_LOG / ENA_BUILD_PLAN are read by the sourced ensure_build_deps (which
# ShellCheck cannot see); reference them so they are not flagged SC2034-unused.
: "${ENA_PM_LOG}" "${ENA_BUILD_PLAN}"

# --- all deps install cleanly -> rc 0 ---------------------------------------
ENA_BUILD_PLAN="make"; RP_FAIL=""; CALLS=""
ensure_build_deps; rc=$?
assert_eq "0" "${rc}" "all build deps install -> rc 0"

# --- REGRESSION GUARD (r22/r24): installs PLAIN kernel-devel, never versioned -
assert_match "${CALLS}" "install kernel-devel" "installs kernel-devel from the container's own repos"
assert_eq "0" "$(printf '%s' "${CALLS}" | grep -c 'kernel-devel-')" \
  "never installs a host-kernel-versioned kernel-devel-<kver> (r22/r24 regression guard)"
assert_match "${CALLS}" "install gcc make" "installs the gcc/make toolchain"

# --- rc mapping the caller branches on --------------------------------------
ENA_BUILD_PLAN="make"; RP_FAIL="gcc make"; CALLS=""
ensure_build_deps; rc=$?
assert_eq "1" "${rc}" "toolchain (gcc/make) install fails -> rc 1"

ENA_BUILD_PLAN="make"; RP_FAIL="kernel-devel"; CALLS=""
ensure_build_deps; rc=$?
assert_eq "3" "${rc}" "kernel-devel unavailable -> rc 3"

# --- dkms is EPEL-only: its failure is best-effort, must NOT fail the deps ----
ENA_BUILD_PLAN="dkms"; RP_FAIL="dkms"; CALLS=""
ensure_build_deps; rc=$?
assert_eq "0" "${rc}" "dkms install fails -> rc 0 (best-effort, does not block the build)"
assert_match "${CALLS}" "install dkms" "dkms plan attempts a dkms install"

t_done
