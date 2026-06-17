#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# build-cleancore.sh  --  clean-core build orchestrator (--all | --ol <N>)
# ----------------------------------------------------------------------------
# Self-contained by design: this script carries its own helper functions inline
# (no shared library / no sourced module), the repository's standard policy for
# user-runnable scripts. It is a thin WRAPPER over the per-OL builders
# tests/cleancore/build-cleancore-ol<MAJOR>.sh: it invokes them as separate
# executables (it does NOT source them), so each builder stays the single,
# self-contained source of truth for its own OL. This wrapper only adds:
#   * a one-call "build every supported OL" mode (--all) and a "build one" mode
#     (--ol <N>), running sequentially and aggregating pass/fail;
#   * a build-ENVIRONMENT (host OS) recognition aligned with the main pipeline's
#     supported execution environments (build-ol-aws-ami.sh / SPEC B.6);
#   * a hard pre-flight gate on the host tools + privileges the builders need.
#
# HOST-OS SUPPORT [SPEC B.6, build-host matrix]. The AMI pipeline supports the
# latest two generations per family: RHEL-family (OL/RHEL/Rocky/Alma/CentOS)
# 10|9, Fedora 44|43, Ubuntu 26.04|24.04, Debian 13|12. The concrete CI target is
# GitHub Actions `ubuntu-latest` (24.04 today -> 26.04), which is in that set.
# A clean-core build is userland-only (no KVM), so it is far more host-agnostic
# than the AMI pipeline: this wrapper therefore RECOGNISES the B.6 set and WARNS
# (does not abort) on a host outside it, while it HARD-FAILS only on a genuinely
# missing prerequisite (root + the unshare/chroot/mknod/curl/tar/xz toolchain).
#
# Usage:
#   bash tests/cleancore/build-cleancore.sh --all [options]
#   bash tests/cleancore/build-cleancore.sh --ol <6|7|8|9|10> [options]
# Options:
#   --out-dir <dir>   directory for the cleancore-ol<N>.tar.gz outputs
#                     (default: ./cleancore-out, created if absent)
#   --work-dir <dir>  scratch base; each OL builds under <dir>/cleancore-ol<N>
#                     (default: the per-builder default, /tmp/cleancore-ol<N>)
#   --continue        in --all, keep going after a failing OL (default: stop)
#   -h | --help
# Env (passed through to the builders): INSECURE_TLS (default per builder = 1 in
#   the sandbox; set 0 on a trusted host).
# Requires: root (unshare/chroot/mknod), unshare, chroot, mknod, curl, tar, xz,
#   gzip, truncate, find. Network reachability per the per-OL builder.
# Exit: 0 = all requested OLs built + self-tested; non-zero = a build failed or a
#   pre-flight prerequisite was missing.
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=""
ONLY_OL=""
OUT_DIR="./cleancore-out"
WORK_BASE=""
CONTINUE_ON_FAIL=0

log()  { printf '%s [build-cleancore] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { log "WARNING: $*" >&2; }
die()  { log "ERROR: $*" >&2; exit 1; }

usage() { sed -n '2,/^# ---.*$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---- args ------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)        MODE="all" ;;
    --ol)         MODE="one"; ONLY_OL="${2:-}"; shift ;;
    --out-dir)    OUT_DIR="${2:-}"; shift ;;
    --work-dir)   WORK_BASE="${2:-}"; shift ;;
    --continue)   CONTINUE_ON_FAIL=1 ;;
    -h|--help)    usage 0 ;;
    *)            die "unknown argument: $1 (use --all or --ol <N>; -h for help)" ;;
  esac
  shift
done

[ -n "${MODE}" ] || die "choose a mode: --all or --ol <N> (-h for help)"

# ---- host-OS recognition vs SPEC B.6 (warn, never abort) -------------------
host_field() {  # host_field <KEY> : read KEY=value from /etc/os-release (no source)
  [ -r /etc/os-release ] || return 0
  sed -n "s/^$1=//p" /etc/os-release | head -1 | tr -d '"'
}
check_host_os() {
  local id ver major status="out"
  id="$(host_field ID)"; ver="$(host_field VERSION_ID)"; major="${ver%%.*}"
  case "${id}" in
    ol|rhel|rocky|almalinux|centos) case "${major}" in 10|9) status="in" ;; esac ;;
    fedora)                         case "${major}" in 44|43) status="in" ;; esac ;;
    ubuntu)                         case "${ver}"   in 26.04|24.04) status="in" ;; esac ;;
    debian)                         case "${major}" in 13|12) status="in" ;; esac ;;
  esac
  if [ "${status}" = "in" ]; then
    log "host: ${id:-unknown} ${ver:-?} -- within the SPEC B.6 build-host matrix"
  else
    warn "host: ${id:-unknown} ${ver:-?} is OUTSIDE the SPEC B.6 build-host matrix"
    warn "(RHEL-family 10|9, Fedora 44|43, Ubuntu 26.04|24.04, Debian 13|12)."
    warn "A clean-core build is userland-only (no KVM) and usually host-agnostic;"
    warn "proceeding. The prerequisite-tool gate below is the real requirement."
  fi
}

# ---- hard pre-flight: privileges + tools the builders need -----------------
require_prereqs() {
  [ "$(id -u)" -eq 0 ] || die "must run as root (the builders need unshare/chroot/mknod). Re-run under sudo."
  local missing="" t
  for t in unshare chroot mknod curl tar xz gzip truncate find; do
    command -v "${t}" >/dev/null 2>&1 || missing="${missing} ${t}"
  done
  [ -z "${missing}" ] || die "missing required host tools:${missing}"
}

# ---- resolve the OL list ---------------------------------------------------
builder_for() { printf '%s/build-cleancore-ol%s.sh' "${SCRIPT_DIR}" "$1"; }

# ---- run -------------------------------------------------------------------
check_host_os
require_prereqs
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

# Build the target list in THIS shell so a validation failure aborts the script
# (a die inside a <(process substitution) would only exit the subshell).
TARGETS=()
if [ "${MODE}" = "one" ]; then
  [ -n "${ONLY_OL}" ] || die "--ol needs a major version (e.g. --ol 6)"
  [ -f "$(builder_for "${ONLY_OL}")" ] || die "no builder for OL${ONLY_OL} ($(builder_for "${ONLY_OL}") not found)"
  TARGETS=("${ONLY_OL}")
else
  # --all: every OL that has a build-cleancore-ol<N>.sh, ascending.
  for n in 5 6 7 8 9 10; do
    if [ -f "$(builder_for "${n}")" ]; then TARGETS+=("${n}"); fi
  done
fi
[ "${#TARGETS[@]}" -gt 0 ] || die "no OL builders found under ${SCRIPT_DIR}"
log "orchestrating clean-core build for OL: ${TARGETS[*]}  (out-dir: ${OUT_DIR})"

n_ok=0; n_fail=0; failed=""
for ol in "${TARGETS[@]}"; do
  out_tarball="${OUT_DIR}/cleancore-ol${ol}.tar.gz"
  builder="$(builder_for "${ol}")"
  log "=== OL${ol}: ${builder##*/} -> ${out_tarball} ==="
  ol_env=()
  if [ -n "${WORK_BASE}" ]; then ol_env=(env "WORK=${WORK_BASE}/cleancore-ol${ol}"); fi
  if "${ol_env[@]}" bash "${builder}" "${out_tarball}"; then
    n_ok=$((n_ok + 1)); log "=== OL${ol}: BUILT OK ==="
  else
    n_fail=$((n_fail + 1)); failed="${failed} ${ol}"
    warn "=== OL${ol}: BUILD FAILED ==="
    if [ "${CONTINUE_ON_FAIL}" -ne 1 ]; then
      die "stopping after OL${ol} (use --continue to build the rest anyway)"
    fi
  fi
done

log "summary: ${n_ok} built, ${n_fail} failed${failed:+ (failed:${failed})}; outputs in ${OUT_DIR}"
[ "${n_fail}" -eq 0 ] || exit 1
