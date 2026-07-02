#!/usr/bin/env bash
#==============================================================================
# install-aws_ena-driver.sh - build (and in production, install) the AWS ENA
# driver on a RHEL-family host. E2': the build is entitlement-gated. In entitled
# mode the script installs gcc + make + kernel-devel-$(uname -r) from the entitled
# repos (via the redhat.repo/cert passthrough) before building. Self-contained;
# tests/aws_ena-driver/; run-ena-buildtest-matrix.sh kicks it with parameters.
#
# Compiles ena.ko OUT OF TREE against the installed kernel-devel headers
#   make -C /usr/src/kernels/<kver> M=<src> modules
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
#==============================================================================
set -uo pipefail

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
BUILT_SRC=""; BUILT_DEST=""; MAKE_LOG=""

# --- container package-manager safety (RHEL6 RHSM stall + timeouts) -----------
# entitlement_certs_present : rc 0 iff >=1 entitlement cert is visible in-container.
entitlement_certs_present() {
  ls /etc/pki/entitlement/*.pem >/dev/null 2>&1 \
    || ls /run/secrets/etc-pki-entitlement/*.pem >/dev/null 2>&1
}
# pm_neutralize_rhsm_if_anonymous : when NO entitlement certs are present, disable
# the subscription-manager/product-id yum|dnf plugins for THIS container only.
# They otherwise contact RHSM and hang indefinitely on unentitled hosts (notably
# bare RHEL6). With certs present (entitled) they are left ON - they work and are
# needed for entitled repos. Container-local; the host is never modified.
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

# ensure_build_deps : ENTITLED path. Install the build toolchain and the
# kernel-devel that MATCHES the running (host) kernel from the entitled repos so
# build_ko finds /usr/src/kernels/$(uname -r). A loadable module must match the
# running kernel exactly; when the container major differs from the host kernel
# (cross-major) that kernel-devel NVR is absent from the container repos and the
# module cannot be built here. rc: 0 ready | 1 toolchain failed | 3 no matching
# kernel-devel. Requires the entitled repo passthrough (redhat.repo + certs).
ensure_build_deps() {
  local mgr krel; mgr="$(ena_pm)"; krel="$(uname -r)"
  log "entitled: installing build deps (gcc make kernel-devel-${krel}) via ${mgr}"
  run_pm "${mgr}" -y install gcc make >/dev/null 2>&1 || return 1
  run_pm "${mgr}" -y install "kernel-devel-${krel}" >/dev/null 2>&1 || return 3
  if [ "${ENA_BUILD_PLAN}" = "dkms" ]; then
    run_pm "${mgr}" -y install dkms >/dev/null 2>&1 || true   # dkms is EPEL-only; best-effort
  fi
  return 0
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
    printf '[aws_ena-driver][installtest][result] {"status":"fail","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"ko_version":"%s","reason":"%s"}\n' \
      "${OSMAJOR}" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "${KVER}" "${BUILT}" "${KO_VERSION}" "$(json_escape "$*")"
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
  [ -n "${v}" ] || v="$(strings "${ko}" 2>/dev/null | sed -n 's/^version=\([0-9][0-9.]*\)$/\1/p' | head -1)"
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
  find "${dest}" -maxdepth 3 -type d -path '*/kernel/linux/ena' | head -1
}

build_ko() {
  local src
  KVER="$(kdevel_kver)"
  [ -n "${KVER}" ] && [ -d "/usr/src/kernels/${KVER}" ] || return 2   # no kernel-devel
  BUILT_DEST="$(mktemp -d)"
  src="$(fetch_src "${BUILT_DEST}")" || return 1
  [ -n "${src}" ] || return 1
  BUILT_SRC="${src}"; MAKE_LOG="${BUILT_DEST}/make.log"
  if make -C "/usr/src/kernels/${KVER}" "M=${src}" modules >"${MAKE_LOG}" 2>&1 && [ -f "${src}/ena.ko" ]; then
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
    printf '[aws_ena-driver][installtest][result] {"status":"ok","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"anonymous","build_plan":"%s","kver":"","built":false,"ko_version":"","reason":"no kernel-devel (anonymous) -> needs-entitlement"}\n' \
      "${OSMAJOR}" "${ENA_VERSION}" "${ENA_BUILD_PLAN}"
    exit 0
  fi
  die "anonymous: kernel-devel unavailable; cannot build (needs entitlement)"
fi

# entitled: install the toolchain + matching kernel-devel from the entitled repos,
# then build out of tree and verify the module reports the requested version
ensure_build_deps; edc=$?
case "${edc}" in
  0) : ;;
  3) die "kernel-devel-$(uname -r) not available in RHEL${OSMAJOR} entitled repos (a loadable module needs an exact match to the running kernel; a cross-major container cannot build here)" ;;
  *) die "entitled build dependencies failed to install (gcc/make) on RHEL${OSMAJOR}" ;;
esac
if build_ko; then
  KO_VERSION="$(ko_module_version "${BUILT_SRC}/ena.ko")"
  if [ -n "${KO_VERSION}" ] && [ "${KO_VERSION}" != "${ENA_VERSION}" ]; then
    dump_build_diag
    die "false-success guard: built ena.ko reports version ${KO_VERSION}, requested ${ENA_VERSION}"
  fi
  BUILT="true"
else
  rc=$?
  case "${rc}" in
    2) die "kernel-devel not installed (cannot build)" ;;
    *) dump_build_diag; die "build failed (make returned non-zero or produced no ena.ko)" ;;
  esac
fi

if [ "${ENA_INSTALLTEST}" = "1" ]; then
  RESULT_EMITTED=1
  printf '[aws_ena-driver][installtest][result] {"status":"ok","tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"ko_version":"%s"}\n' \
    "${OSMAJOR}" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "${KVER}" "${BUILT}" "${KO_VERSION}"
  [ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
  exit 0
fi

# --- production mode: install the freshly built module ------------------------
log "installing ena.ko ${KO_VERSION:-?} for kernel ${KVER}"
make -C "/usr/src/kernels/${KVER}" "M=${BUILT_SRC}" modules_install >/dev/null 2>&1 || die "modules_install failed"
depmod -a "${KVER}" || true
[ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
log "done (load + device attach is L4 - not attempted here)"
