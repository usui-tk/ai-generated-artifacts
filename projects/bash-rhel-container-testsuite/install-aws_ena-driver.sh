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
#       ENA_BUILD_PLAN  (make|dkms; default make)
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
ENA_BUILD_PLAN="${ENA_BUILD_PLAN:-make}"
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
  log "entitled: installing build deps (gcc make elfutils-libelf-devel kernel-devel) via ${mgr}"
  run_pm "${mgr}" -y install gcc make elfutils-libelf-devel >>"${ENA_PM_LOG}" 2>&1 || return 1
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
  local k
  k="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel 2>/dev/null | sort -V | tail -1)"
  [ -n "${k}" ] || k="$(find /usr/src/kernels -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -1)"
  printf '%s' "${k}"
}

# ko_module_version <ena.ko> : the version the built module reports (modinfo, or
# the embedded "version=" string if modinfo is absent). The false-success guard.
ko_module_version() {
  local ko="$1" v=""
  if command -v modinfo >/dev/null 2>&1; then
    v="$(modinfo -F version "${ko}" 2>/dev/null | head -1)"
  fi
  [ -n "${v}" ] || v="$(strings "${ko}" 2>/dev/null | sed -n 's/^version=\([0-9][0-9.]*\)/\1/p' | head -1)"
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
  BUILT_DEST="$(mktemp -d)"
  src="$(fetch_src "${BUILT_DEST}")" || return 3   # r49: fetch/extract/locate, NOT make
  [ -n "${src}" ] || return 3
  BUILT_SRC="${src}"; MAKE_LOG="${BUILT_DEST}/make.log"
  # r52: build through the driver's VENDORED build system, never raw kbuild.
  # Modern ENA sources require a generated config.h (feature-detection via
  # the bundled configure.sh, run by the vendored Makefile's config.h rule);
  # the old direct `make -C <kernel> M=<src> modules` bypassed it and every
  # real entitled build died with `fatal error: config.h` (reproduced and
  # fixed-form verified in a ubi9 chroot against RHCK 5.14 headers). This is
  # also how the OL original built it (make -C <src> BUILD_KERNEL=...).
  # KERNEL_BUILD_DIR is pinned to /usr/src/kernels/<kver> because containers
  # have no /lib/modules/<kver>/build symlink (the vendored default).
  if make -C "${src}" "KERNEL_BUILD_DIR=/usr/src/kernels/${KVER}" "BUILD_KERNEL=${KVER}" >"${MAKE_LOG}" 2>&1 \
     && [ -f "${src}/ena.ko" ]; then
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
if [ "${bko_rc}" = "0" ]; then
  KO_VERSION="$(ko_module_version "${BUILT_SRC}/ena.ko")"
  if [ -n "${KO_VERSION}" ] && [ "${KO_VERSION}" != "${ENA_VERSION}" ]; then
    dump_build_diag
    die "false-success guard: built ena.ko reports version ${KO_VERSION}, requested ${ENA_VERSION}"
  fi
  BUILT="true"
else
  case "${bko_rc}" in
    2) die "kernel-devel not installed (cannot build)" ;;
    *) dump_build_diag; die "build failed (make returned non-zero or produced no ena.ko)" ;;
  esac
fi

if [ "${ENA_INSTALLTEST}" = "1" ]; then
  RESULT_EMITTED=1
  printf '[aws_ena-driver][installtest][result] {"status":"ok","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"ko_version":"%s","ena_express":"%s"}\n' \
    "${OSMAJOR}" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "${KVER}" "${BUILT}" "${KO_VERSION}" "$(ena_express_verdict "${ENA_VERSION}")"
  [ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
  exit 0
fi

# --- production mode: install the freshly built module ------------------------
log "installing ena.ko ${KO_VERSION:-?} for kernel ${KVER} (ENA Express: $(ena_express_verdict "${ENA_VERSION}"))"
make -C "/usr/src/kernels/${KVER}" "M=${BUILT_SRC}" modules_install >/dev/null 2>&1 || die "modules_install failed"
depmod -a "${KVER}" || true
[ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
log "done (load + device attach is L4 - not attempted here)"
