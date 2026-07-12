#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Build (and optionally install) the Amazon ENA network driver from source
#   against the container/host kernel-devel tree; in test mode, emit a
#   single-line [result] JSON (ok / build-fail / needs-entitlement). The
#   result also reports the ENA Express driver-version-floor readiness
#   (express-ready / bandwidth-only / not-ready) - a driver-capability
#   signal only; see the ena_express_verdict() helper for the full caveat.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl, tar; gcc/make + kernel-devel (entitled repos in containers);
#   network to github.com for the ENA source archive.
# ----- Usage examples -------------------------------------------------------
#   sudo bash install-aws_ena-driver.sh                      # build + install
#   ENA_BUILDTEST=1 ENA_VERSION=2.13.0 bash install-aws_ena-driver.sh
# ----- Known limitations ----------------------------------------------------
#   Module LOAD cannot be exercised in a container (shared host kernel) - load
#   is L4; anonymous UBI has no kernel-devel -> verdict needs-entitlement.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# install-aws_ena-driver.sh - build (and in production, install) the AWS ENA
# driver on a RHEL-family host. E2': the build is entitlement-gated. In entitled
# mode the script installs gcc + make + kernel-devel from the entitled repos (via
# the redhat.repo/cert passthrough) and builds against THAT kernel-devel tree -
# each RHEL major compiles against its own kernel headers. Self-contained;
# tests/aws_ena-driver/; run-ena-buildtest-matrix.sh kicks it with parameters.
#
# Compiles ena.ko OUT OF TREE against the installed kernel-devel headers
#   make -C <src> KERNEL_BUILD_DIR=/usr/src/kernels/<kver> BUILD_KERNEL=<kver>
# (the driver's vendored build system, which generates config.h first),
# independent of the running host kernel. All Oracle UEK handling is removed
# (stock RHEL kernel: `rpm -q kernel`). Module LOAD is never attempted (L4).
#
# Two modes:
#   1. Production (ENA_INSTALLTEST=0): build, then `make modules_install` + depmod.
#   2. Test (ENA_INSTALLTEST=1): build only; emit one
#      [aws_ena-driver][installtest][result] {json} line.
#
# False-success guard: the built ena.ko's modinfo version must match the request
# (ko_version), so a build that silently produced no/old module is not "ok". On
# build failure, dump_build_diag surfaces the captured make.log. Anonymous mode
# has no kernel-devel -> built=false / needs-entitlement (no build attempted).
# Every failure path still emits {"status":"fail",...} (die).
#
# Env:  ENA_VERSION     (default: per-major pin below)
#       ENA_INSTALLTEST (0|1; default 0)
#       ENA_ENTITLEMENT (entitled|anonymous; default entitled)
#       ENA_BUILD_PLAN  (make|dkms; default dkms since r65 - OL parity.
#                        r68: under INSTALLTEST the dkms plan is ONE-SHOT -
#                        a dkms build failure is terminal (no make retry) and
#                        a missing dkms binary is a harness error (no result
#                        row). In production mode, plain make remains the
#                        OL-parity fallback when dkms is NOT INSTALLABLE.)
#       ENA_SRC_BASEURL (default https://github.com/amzn/amzn-drivers)
#       INSECURE_TLS    (0|1; default 0)
#
# ENA EXPRESS READINESS ("ena_express" in the [result] JSON, and in the
# production-mode install log line). Pure function of ENA_VERSION via
# ena_express_verdict() (AWS ena-express.html: >= 2.2.9 full bandwidth,
# >= 2.8.0 ena_srd_* metrics -> "express-ready"). REUSE-BY-COPY of
# tests/aws_ena-driver/run-ena-buildtest-matrix.sh's helper, kept identical
# (tests/t010_enaverdict.sh). NOT an eligibility check: ENA Express is
# enabled via the AWS API EnaSrdEnabled ENI-attachment attribute, unrelated
# to this script, and gated by instance type - meeting the floor is
# necessary, not sufficient (a "built":true build already carries the same
# necessary-not-sufficient caveat for module load, which is always L4 here).
#==============================================================================
set -euo pipefail

ENA_VERSION="${ENA_VERSION:-}"
ENA_INSTALLTEST="${ENA_INSTALLTEST:-0}"
ENA_ENTITLEMENT="${ENA_ENTITLEMENT:-entitled}"
ENA_BUILD_PLAN="${ENA_BUILD_PLAN:-dkms}"
ENA_SRC_BASEURL="${ENA_SRC_BASEURL:-https://github.com/amzn/amzn-drivers}"
INSECURE_TLS="${INSECURE_TLS:-0}"

# Per-RHEL-major pins: the newest ENA driver that BUILDS on each target's
# kernel/toolchain. RHEL 6 (old EL6 kernel + gcc) is pinned to an older driver
# that still compiles there; RHEL 7-10 take the current 2.17.0. Explicit
# ENA_VERSION overrides (the matrix passes one in test mode).
ENA_VERSION_RHEL6="${ENA_VERSION_RHEL6:-2.9.1}"
ENA_VERSION_RHEL7="${ENA_VERSION_RHEL7:-2.17.0}"
ENA_VERSION_RHEL8="${ENA_VERSION_RHEL8:-2.17.0}"
ENA_VERSION_RHEL9="${ENA_VERSION_RHEL9:-2.17.0}"
ENA_VERSION_RHEL10="${ENA_VERSION_RHEL10:-2.17.0}"

OSMAJOR=""; BUILT="false"; KVER=""; KO_VERSION=""; RESULT_EMITTED=0
ENA_PM_LOG=""
BUILT_SRC=""; BUILT_DEST=""; MAKE_LOG=""

# --- container package-manager safety (RHEL6 RHSM stall + timeouts) -----------
# entitlement_certs_present : rc 0 iff >=1 entitlement cert is visible in-container.
entitlement_certs_present() {
  ls /etc/pki/entitlement/*.pem >/dev/null 2>&1 \
    || ls /run/secrets/etc-pki-entitlement/*.pem >/dev/null 2>&1
}
# pm_neutralize_rhsm_if_anonymous : when NO entitlement certs are present, disable
# the subscription-manager/product-id yum|dnf plugins for THIS container only.
# DEFENSIVE (D-S4, r46): the historically observed RHSM-contact hang did NOT
# reproduce in the 2026-07-04 probe runs (EL6 included); disabling in a
# certless container is harmless and guards unknown environments. With certs
# present (RHSM auto-injection) they stay ON - they generate the per-major
# entitled redhat.repo. Container-local; the host is never modified.
pm_neutralize_rhsm_if_anonymous() {
  entitlement_certs_present && return 0
  local d p
  for d in /etc/yum/pluginconf.d /etc/dnf/plugins; do
    [ -d "${d}" ] || continue
    for p in subscription-manager product-id; do
      printf '[main]\nenabled=0\n' > "${d}/${p}.conf" 2>/dev/null || true
    done
  done
}
# run_pm : run a package-manager command bounded by PKG_TIMEOUT (default 300s) so a
# stalled repo/plugin op can never hang the run. No-timeout fallback if 'timeout'
# is somehow absent.
run_pm() {
  if command -v timeout >/dev/null 2>&1; then timeout "${PKG_TIMEOUT:-300}" "$@"; else "$@"; fi
}

# ena_pm : the package manager available in this image (dnf on 8+, yum on 6/7).
ena_pm() { command -v dnf >/dev/null 2>&1 && printf 'dnf' || printf 'yum'; }

# ensure_build_deps : ENTITLED path. Install the build toolchain and kernel-devel
# from the CONTAINER's OWN entitled repos, then build against that installed
# kernel-devel tree (build_ko uses the newest /usr/src/kernels/<kver>). This is a
# COMPILE test - each RHEL major builds against its own kernel headers, independent
# of the running host kernel; module LOAD is never attempted in a container (L4).
# rc: 0 ready | 1 toolchain failed | 3 kernel-devel unavailable in the repos.
# Requires the entitled repo passthrough (redhat.repo + certs).
ensure_build_deps() {
  local mgr; mgr="$(ena_pm)"
  ENA_PM_LOG="$(mktemp)"
  # r48: elfutils-libelf-devel added - EL8+ kbuild (objtool/resolve_btfids)
  # needs libelf headers for external module builds; harmless on 6/7. The
  # 2026-07-04 smoke E2E showed make failing on every major without it (the
  # probe's measured build package set already included it).
  # r56: perl added - RHEL 6 kernel 2.6.32 kbuild uses recordmcount.pl (a
  # perl script) during module compilation; kernel 3.x+ replaced it with a
  # C implementation, so only EL6 actually needs it, but it is harmless on
  # newer majors (perl is a standard base package).
  log "entitled: installing build deps (gcc make perl elfutils-libelf-devel kernel-devel) via ${mgr}"
  run_pm "${mgr}" -y install gcc make perl elfutils-libelf-devel >>"${ENA_PM_LOG}" 2>&1 || return 1
  run_pm "${mgr}" -y install kernel-devel >>"${ENA_PM_LOG}" 2>&1 || return 3
  if [ "${ENA_BUILD_PLAN}" = "dkms" ]; then
    run_pm "${mgr}" -y install dkms >>"${ENA_PM_LOG}" 2>&1 || true   # dkms is EPEL-only; best-effort
  fi
  return 0
}

# dump_pm_diag : surface the tail of the package-manager log so a failed entitled
# dep install shows WHY (missing NVR, disabled repo, TLS/entitlement error, ...).
dump_pm_diag() {
  local pfx="[install-aws_ena-driver][ERROR]"
  if [ -n "${ENA_PM_LOG}" ] && [ -s "${ENA_PM_LOG}" ]; then
    printf '%s package-manager log (last 20 lines):\n' "${pfx}" >&2
    tail -n 20 "${ENA_PM_LOG}" | sed "s/^/${pfx}   /" >&2
  else
    printf '%s   (no package-manager log captured)\n' "${pfx}" >&2
  fi
}

log() { printf '%s [install-aws_ena-driver] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# dump_build_diag : best-effort surface of the captured make.log on failure, so a
# compile error is not an opaque non-zero. Prefixed lines stay greppable.
dump_build_diag() {
  local pfx="[install-aws_ena-driver][ERROR]"
  printf '%s ---- build diagnostics (ENA %s, kernel %s) ----\n' "${pfx}" "${ENA_VERSION:-?}" "${KVER:-?}" >&2
  if [ -n "${MAKE_LOG}" ] && [ -f "${MAKE_LOG}" ]; then
    sed "s/^/${pfx}   /" "${MAKE_LOG}" >&2 || true
  else
    printf '%s   (no make.log captured)\n' "${pfx}" >&2
  fi
  printf '%s ---- end build diagnostics ----\n' "${pfx}" >&2
}

die() {
  log "ERROR: $*"
  if [ "${ENA_INSTALLTEST}" = "1" ] && [ "${RESULT_EMITTED}" = "0" ]; then
    RESULT_EMITTED=1
    printf '[aws_ena-driver][installtest][result] {"status":"fail","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"ko_version":"%s","ena_express":"%s","reason":"%s"}\n' \
      "${OSMAJOR}" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "${KVER}" "${BUILT}" "${KO_VERSION}" "$(ena_express_verdict "${ENA_VERSION}")" "$(json_escape "$*")"
  fi
  exit 1
}

os_major() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ( . /etc/os-release; printf '%s' "${VERSION_ID%%.*}" )
  elif [ -r /etc/redhat-release ]; then
    sed -n 's/.*release \([0-9]\+\).*/\1/p' /etc/redhat-release | head -1
  fi
}

kdevel_kver() {
  # r67: `rpm -q` prints "package kernel-devel is not installed" on STDOUT
  # (rc != 0) - the old pipeline captured that message as the kver, so the
  # directory fallback never ran and the garbage text leaked into the
  # [result] kver field. Gate on rpm's exit code instead, then validate the
  # newest NVR against the tree the build actually uses
  # (/usr/src/kernels/<kver> is the ground truth for make/dkms); if the
  # rpmdb answer has no matching tree, fall back to the directory scan.
  # This keeps the helper correct however kernel-devel arrived - RHSM
  # repos, RHUI repos (planned entitled-path work), or pre-baked into an
  # image/AMI with a stale rpmdb.
  local k rpmq
  rpmq="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel 2>/dev/null)" || rpmq=""
  k="$(printf '%s\n' "${rpmq}" | sort -V | tail -1)"
  if [ -z "${k}" ] || [ ! -d "/usr/src/kernels/${k}" ]; then
    k="$(find /usr/src/kernels -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -1)"
  fi
  printf '%s' "${k}"
}

# ko_module_version <ena.ko> : the version the built module reports (modinfo, or
# the embedded "version=" string if modinfo is absent). The false-success guard.
ko_module_version() {
  local ko="$1" v=""
  if command -v modinfo >/dev/null 2>&1; then
    v="$(modinfo -F version "${ko}" 2>/dev/null | head -1 || true)"
  fi
  [ -n "${v}" ] || v="$(strings "${ko}" 2>/dev/null | sed -n 's/^version=\([0-9][0-9.]*\)/\1/p' | head -1 || true)"
  # r52: the built module reports a suffixed version (measured: 2.17.0 builds
  # as "2.17.0g") - normalize to the numeric prefix so the false-success
  # guard compares like with like.
  v="${v%%[!0-9.]*}"
  printf '%s' "${v}"
}

fetch_src() {
  local dest="$1" tag="ena_linux_${ENA_VERSION}" url tar
  url="${ENA_SRC_BASEURL}/archive/refs/tags/${tag}.tar.gz"
  tar="${dest}/ena-src.tar.gz"
  local -a opts=(-fsSL --retry 2 -o "${tar}")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(-k)
  curl "${opts[@]}" "${url}" || return 1
  tar -xzf "${tar}" -C "${dest}" || return 1
  # r49: the tarball root is amzn-drivers-<tag>/, so the ena dir sits at
  # depth 4 from dest - the old -maxdepth 3 NEVER found it and every real
  # entitled build failed with a misleading "build failed (make ...)" (the
  # bug stayed latent while the legacy mounts kept builds from running).
  find "${dest}" -maxdepth 5 -type d -path '*/kernel/linux/ena' | head -1
}

build_ko() {
  local src
  KVER="$(kdevel_kver)"
  [ -n "${KVER}" ] && [ -d "/usr/src/kernels/${KVER}" ] || return 2   # no kernel-devel
  # r68: INSTALLTEST measures the PRODUCTION method only (DKMS one-shot).
  # A missing dkms binary under the dkms plan is a provisioning failure of
  # the test image (r65 bakes EPEL + dkms into every image), not a version
  # verdict -> rc 4: the caller reports a harness error and emits NO
  # [result] row, so environment failures never pollute version statistics.
  if [ "${ENA_INSTALLTEST}" = "1" ] && [ "${ENA_BUILD_PLAN}" = "dkms" ] \
     && ! command -v dkms >/dev/null 2>&1; then
    return 4
  fi
  BUILT_DEST="$(mktemp -d)"
  src="$(fetch_src "${BUILT_DEST}")" || return 3   # r49: fetch/extract/locate, NOT make
  [ -n "${src}" ] || return 3
  BUILT_SRC="${src}"; MAKE_LOG="${BUILT_DEST}/make.log"
  if [ ! -e "/lib/modules/${KVER}/build" ] && [ -d "/usr/src/kernels/${KVER}" ]; then
    mkdir -p "/lib/modules/${KVER}"
    ln -sf "/usr/src/kernels/${KVER}" "/lib/modules/${KVER}/build"
  fi
  # r65: DKMS-first build (OL parity). dkms add/build/install is the production
  # method; plain-make is a fallback when dkms is unavailable.
  if [ "${ENA_BUILD_PLAN}" = "dkms" ] && command -v dkms >/dev/null 2>&1; then
    log "ENA ${ENA_VERSION}: DKMS build for kernel ${KVER}"
    local dkms_src="/usr/src/amzn-drivers-${ENA_VERSION}"
    rm -rf "${dkms_src}"
    cp -a "$(dirname "$(dirname "$(dirname "${src}")")")" "${dkms_src}"
    cat > "${dkms_src}/dkms.conf" <<DKMSEOF
PACKAGE_NAME="ena"
PACKAGE_VERSION="${ENA_VERSION}"
CLEAN="make -C kernel/linux/ena clean"
MAKE="make -C kernel/linux/ena/ BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_NAME[0]="ena"
BUILT_MODULE_LOCATION="kernel/linux/ena"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="ena"
REMAKE_INITRD="no"
AUTOINSTALL="yes"
DKMSEOF
    dkms remove -m amzn-drivers -v "${ENA_VERSION}" --all >/dev/null 2>&1 || true
    if dkms add -m amzn-drivers -v "${ENA_VERSION}" >"${MAKE_LOG}" 2>&1 \
       && dkms build -m amzn-drivers -v "${ENA_VERSION}" -k "${KVER}" >>"${MAKE_LOG}" 2>&1 \
       && dkms install -m amzn-drivers -v "${ENA_VERSION}" -k "${KVER}" --force >>"${MAKE_LOG}" 2>&1; then
      local dkms_ko
      # r69: dkms's install destination differs by dkms GENERATION - EL10's
      # dkms 3.x honours dkms.conf's /updates, while the older dkms on
      # EL6-9 installs to extra/ (2026-07-06 E2E evidence: RHEL 7/9 logged
      # "Installing to /lib/modules/<kver>/extra/" and the updates/-only
      # lookup missed it, false-failing 116 cells across four majors).
      # Search both; the KO_VERSION guard downstream keeps the
      # installed-version-is-authoritative principle (OL parity).
      dkms_ko="$(find /lib/modules/"${KVER}" -name 'ena.ko' \( -path '*/updates/*' -o -path '*/extra/*' \) 2>/dev/null | head -1)"
      if [ -n "${dkms_ko}" ]; then
        cp -f "${dkms_ko}" "${src}/ena.ko"
        ENA_BUILD_PLAN_USED="dkms"
        return 0
      fi
      log "WARNING: dkms returned 0 but no ena.ko under /lib/modules/${KVER}/{updates,extra}"
    fi
    # r69 (OL parity: _ena_first_make_error): on a dkms build failure the
    # compiler output lives in the DKMS tree's make.log - dkms stdout only
    # carries the generic "Error! Bad return status" line. Fold that
    # make.log into the captured log so the r61 first-error extraction
    # reports the real compiler error instead of the generic fallback.
    local dkms_ml
    dkms_ml="$(find "/var/lib/dkms/amzn-drivers/${ENA_VERSION}" -name 'make.log' 2>/dev/null | head -1)"
    if [ -n "${dkms_ml}" ]; then
      cat "${dkms_ml}" >>"${MAKE_LOG}" 2>/dev/null || true
    fi
    # r68: a dkms BUILD failure is terminal - NO plain-make retry (OL parity:
    # install-ena-driver.sh dies on dkms failure; its make path is only the
    # dkms-NOT-INSTALLABLE environment fallback, never a second build
    # attempt). Re-compiling via make would double the work per failing cell
    # and could report "ok" for a version the production method cannot build.
    return 1
  fi
  # dkms unavailable (or explicit ENA_BUILD_PLAN=make override): OL-parity
  # PRODUCTION fallback - the driver still installs, but will NOT auto-rebuild
  # across kernel upgrades. INSTALLTEST never reaches here under the dkms plan
  # (rc-4 guard above); in production mode this mirrors install-ena-driver.sh.
  if [ "${ENA_BUILD_PLAN}" = "dkms" ]; then
    log "WARNING: dkms not available; falling back to a plain make build (no auto-rebuild on kernel upgrade)"
  fi
  if make -C "${src}" "KERNEL_BUILD_DIR=/usr/src/kernels/${KVER}" "BUILD_KERNEL=${KVER}" >"${MAKE_LOG}" 2>&1 \
     && [ -f "${src}/ena.ko" ]; then
    ENA_BUILD_PLAN_USED="make"
    return 0
  fi
  return 1
}

resolve_version() {
  [ -n "${ENA_VERSION}" ] && return 0
  case "$(os_major)" in
    6)  ENA_VERSION="${ENA_VERSION_RHEL6}" ;;
    7)  ENA_VERSION="${ENA_VERSION_RHEL7}" ;;
    8)  ENA_VERSION="${ENA_VERSION_RHEL8}" ;;
    9)  ENA_VERSION="${ENA_VERSION_RHEL9}" ;;
    10) ENA_VERSION="${ENA_VERSION_RHEL10}" ;;
    *)  ENA_VERSION="2.17.0" ;;
  esac
}

# ena_express_verdict <version> : AWS ENA Express driver-version floor
# (ena-express.html: >= 2.2.9 full bandwidth, >= 2.8.0 ena_srd_* metrics).
# REUSE-BY-COPY of the tests/aws_ena-driver/run-ena-buildtest-matrix.sh
# helper; kept identical - verified by tests/t010_enaverdict.sh. Pure
# function of ENA_VERSION only - NOT an eligibility check: ENA Express is
# enabled via the AWS API EnaSrdEnabled ENI-attachment attribute (unrelated
# to this script) and gated by instance type; meeting the floor is
# necessary, not sufficient (a build "ok" already carries the same caveat).
ena_express_verdict() {
  local v="${1:-}" hi
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  hi="$(printf '%s\n2.8.0\n' "${v}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  if [ "${v}" = "2.8.0" ] || [ "${hi}" = "${v}" ]; then printf 'express-ready'; return 0; fi
  hi="$(printf '%s\n2.2.9\n' "${v}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  if [ "${v}" = "2.2.9" ] || [ "${hi}" = "${v}" ]; then printf 'bandwidth-only'; return 0; fi
  printf 'not-ready'
}

# Tests source this script for the pure pin/resolver/introspection logic without
# building: ENA_LIB_ONLY=1 stops here, after the helpers + per-major pins.
[ "${ENA_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

trap 'die "unexpected error (line ${LINENO})"' ERR

OSMAJOR="$(os_major)"
pm_neutralize_rhsm_if_anonymous
resolve_version

# anonymous: no kernel-devel -> do not build; report needs-entitlement
if [ "${ENA_ENTITLEMENT}" = "anonymous" ]; then
  if [ "${ENA_INSTALLTEST}" = "1" ]; then
    RESULT_EMITTED=1
    printf '[aws_ena-driver][installtest][result] {"status":"ok","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"anonymous","build_plan":"%s","kver":"","built":false,"ko_version":"","ena_express":"%s","reason":"no kernel-devel (anonymous) -> needs-entitlement"}\n' \
      "${OSMAJOR}" "${ENA_VERSION}" "${ENA_BUILD_PLAN}" "$(ena_express_verdict "${ENA_VERSION}")"
    exit 0
  fi
  die "anonymous: kernel-devel unavailable; cannot build (needs entitlement)"
fi

# entitled: install the toolchain + matching kernel-devel from the entitled repos,
# then build out of tree and verify the module reports the requested version
# NB: guard with || so a non-zero return does NOT trip the ERR trap (which would
# mask the real reason with a generic "unexpected error").
edc=0; ensure_build_deps || edc=$?
case "${edc}" in
  0) : ;;
  3) dump_pm_diag; die "kernel-devel not available/installable from RHEL${OSMAJOR} entitled repos (see the package-manager log above)" ;;
  *) dump_pm_diag; die "entitled build dependencies failed to install (gcc/make/kernel-devel) on RHEL${OSMAJOR}" ;;
esac
bko_rc=0; build_ko || bko_rc=$?
if [ "${bko_rc}" = "3" ]; then
  die "source fetch/extract failed (github reachable? tar/gzip present? tag ena_linux_${ENA_VERSION} published?)"
fi
if [ "${bko_rc}" = "4" ]; then
  # r68: dkms missing from the test image = PROVISIONING failure, not a
  # version verdict. Deliberately emit NO [result] row (RESULT_EMITTED=1
  # suppresses die()'s emission too): the matrix runner records a no-result
  # exit as a harness-error row, keeping environment failures out of the
  # per-version statistics. The runner's per-major dkms preflight normally
  # catches this before any cell runs; this is the in-container defense.
  RESULT_EMITTED=1
  log "ERROR: dkms is not available in this test image (r65 provisioning bakes EPEL + dkms in) - provisioning failure, not a version verdict; exiting without a [result] row"
  exit 1
fi
if [ "${bko_rc}" = "0" ]; then
  KO_VERSION="$(ko_module_version "${BUILT_SRC}/ena.ko")"
  if [ -n "${KO_VERSION}" ] && [ "${KO_VERSION}" != "${ENA_VERSION}" ]; then
    dump_build_diag
    die "false-success guard: built ena.ko reports version ${KO_VERSION}, requested ${ENA_VERSION}"
  fi
  BUILT="true"
else
  # r61: extract the FIRST compiler error from make.log so the ledger reason
  # carries the specific kernel-API error (e.g. "implicit declaration of
  # function 'from_timer'") instead of the generic "build failed" message.
  # r66: this runs at TOP LEVEL (not in a function) - 'local' here is a bash
  # error ("local: can only be used in a function") that trips the ERR trap
  # and masked every real compile error as "unexpected error (line NNN)".
  first_error=""
  if [ -f "${MAKE_LOG}" ]; then
    first_error="$(grep -m1 ' error:' "${MAKE_LOG}" \
      | sed 's/^.*error: //' | head -c 200 || true)"
  fi
  case "${bko_rc}" in
    2) die "kernel-devel not installed (cannot build)" ;;
    *)
      dump_build_diag
      if [ -n "${first_error}" ]; then
        die "build failed (${first_error})"
      else
        die "build failed (make returned non-zero or produced no ena.ko)"
      fi
      ;;
  esac
fi

if [ "${ENA_INSTALLTEST}" = "1" ]; then
  RESULT_EMITTED=1
  # r66: top-level code - no 'local' (same class of bug as the fail branch;
  # this one fired AFTER RESULT_EMITTED=1, so die() emitted NO [result] line
  # and every successful build was recorded as a harness-error).
  _dkms_used="false"
  [ "${ENA_BUILD_PLAN_USED:-make}" = "dkms" ] && _dkms_used="true"
  printf '[aws_ena-driver][installtest][result] {"status":"ok","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"ko_version":"%s","dkms":%s,"ena_express":"%s"}\n' \
    "${OSMAJOR}" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "${KVER}" "${BUILT}" "${KO_VERSION}" "${_dkms_used}" "$(ena_express_verdict "${ENA_VERSION}")"
  [ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
  exit 0
fi

# --- production mode: install the freshly built module ------------------------
log "installing ena.ko ${KO_VERSION:-?} for kernel ${KVER} (ENA Express: $(ena_express_verdict "${ENA_VERSION}"))"
make -C "/usr/src/kernels/${KVER}" "M=${BUILT_SRC}" modules_install >/dev/null 2>&1 || die "modules_install failed"
depmod -a "${KVER}" || true
[ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
log "done (load + device attach is L4 - not attempted here)"
