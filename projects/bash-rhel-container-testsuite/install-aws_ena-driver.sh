#!/usr/bin/env bash
#==============================================================================
# install-aws_ena-driver.sh - build (and in production, install) the AWS ENA
# driver on a RHEL-family host. E2': the build is entitlement-gated (kernel-devel
# + gcc + make come from the entitled repos). Self-contained. Named to match
# tests/aws_ena-driver/; run-ena-buildtest-matrix.sh kicks it with parameters.
#
# Compiles ena.ko OUT OF TREE against the installed kernel-devel headers
#   make -C /usr/src/kernels/<kver> M=<src> modules
# independent of the running host kernel. All Oracle UEK handling is removed
# (stock RHEL kernel: `rpm -q kernel`). Module LOAD is never attempted (L4).
#
# Two modes:
#   1. Production (ENA_INSTALLTEST=0): build and `make modules_install` + depmod.
#   2. Test (ENA_INSTALLTEST=1): build only; emit one
#      [aws_ena-driver][installtest][result] {json} line for the matrix ledger.
#
# Anonymous mode has no kernel-devel -> the script does NOT build and emits
# built=false / reason=no-kernel-devel (the matrix verdict -> needs-entitlement).
#
# Env:  ENA_VERSION     (e.g. 2.17.0; required)
#       ENA_INSTALLTEST (0|1; default 0)
#       ENA_ENTITLEMENT (entitled|anonymous; default entitled)
#       ENA_BUILD_PLAN  (make|dkms; default make)
#       ENA_SRC_BASEURL (default https://github.com/amzn/amzn-drivers)
#       INSECURE_TLS    (0|1; default 0)
# Requires (entitled): kernel-devel, gcc, make, tar, curl. Network: github.com.
#==============================================================================
set -uo pipefail

ENA_VERSION="${ENA_VERSION:-}"
ENA_INSTALLTEST="${ENA_INSTALLTEST:-0}"

# Per-RHEL-major pins: the ENA driver version the build matrix validated for each
# major - the newest release that BUILDS on that target's kernel/toolchain. RHEL 6
# (old EL6 kernel + gcc) is pinned to an older driver that still compiles there;
# RHEL 7-10 take the current 2.17.0. An explicit ENA_VERSION overrides these (the
# matrix passes one in test mode).
ENA_VERSION_RHEL6="${ENA_VERSION_RHEL6:-2.9.1}"
ENA_VERSION_RHEL7="${ENA_VERSION_RHEL7:-2.17.0}"
ENA_VERSION_RHEL8="${ENA_VERSION_RHEL8:-2.17.0}"
ENA_VERSION_RHEL9="${ENA_VERSION_RHEL9:-2.17.0}"
ENA_VERSION_RHEL10="${ENA_VERSION_RHEL10:-2.17.0}"
ENA_ENTITLEMENT="${ENA_ENTITLEMENT:-entitled}"
ENA_BUILD_PLAN="${ENA_BUILD_PLAN:-make}"
ENA_SRC_BASEURL="${ENA_SRC_BASEURL:-https://github.com/amzn/amzn-drivers}"
INSECURE_TLS="${INSECURE_TLS:-0}"

log() { printf '%s [install-aws_ena-driver] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

os_major() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ( . /etc/os-release; printf '%s' "${VERSION_ID%%.*}" )
  elif [ -r /etc/redhat-release ]; then
    sed -n 's/.*release \([0-9]\+\).*/\1/p' /etc/redhat-release | head -1
  fi
}

# the kernel-devel tree to build against (independent of the running kernel).
kdevel_kver() {
  local k
  k="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel 2>/dev/null | sort -V | tail -1)"
  [ -n "${k}" ] || k="$(find /usr/src/kernels -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -1)"
  printf '%s' "${k}"
}

emit_result() { # <built> <kver> <reason>
  printf '[aws_ena-driver][installtest][result] {"tool":"aws_ena-driver","osmajor":"%s","ena_version":"%s","entitlement":"%s","build_plan":"%s","kver":"%s","built":%s,"reason":"%s"}\n' \
    "$(os_major)" "${ENA_VERSION}" "${ENA_ENTITLEMENT}" "${ENA_BUILD_PLAN}" "$2" "$1" "$3"
}

fetch_src() { # <destdir> -> rc 0, echoes the ena source dir
  local dest="$1" tag="ena_linux_${ENA_VERSION}" url tar
  url="${ENA_SRC_BASEURL}/archive/refs/tags/${tag}.tar.gz"
  tar="${dest}/ena-src.tar.gz"
  local -a opts=(-fsSL --retry 2 -o "${tar}")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(-k)
  curl "${opts[@]}" "${url}" || return 1
  tar -xzf "${tar}" -C "${dest}" || return 1
  find "${dest}" -maxdepth 3 -type d -path '*/kernel/linux/ena' | head -1
}

build_ko() { # rc 0 if ena.ko is produced
  local kver src dest
  kver="$(kdevel_kver)"
  [ -n "${kver}" ] && [ -d "/usr/src/kernels/${kver}" ] || return 2   # no kernel-devel
  dest="$(mktemp -d)"
  src="$(fetch_src "${dest}")" || { rm -rf "${dest}"; return 1; }
  [ -n "${src}" ] || { rm -rf "${dest}"; return 1; }
  if make -C "/usr/src/kernels/${kver}" "M=${src}" modules >/dev/null 2>&1 && [ -f "${src}/ena.ko" ]; then
    BUILT_KVER="${kver}"; BUILT_SRC="${src}"; BUILT_DEST="${dest}"
    return 0
  fi
  rm -rf "${dest}"; return 1
}

BUILT_KVER=""; BUILT_SRC=""; BUILT_DEST=""

run_build() { # echoes built(true|false), kver, reason via globals; rc per outcome
  if [ "${ENA_ENTITLEMENT}" = "anonymous" ]; then
    OUT_BUILT=false; OUT_KVER=""; OUT_REASON="no kernel-devel (anonymous) -> needs-entitlement"
    return 0
  fi
  if build_ko; then
    OUT_BUILT=true; OUT_KVER="${BUILT_KVER}"; OUT_REASON=""
  else
    case "$?" in
      2) OUT_BUILT=false; OUT_KVER=""; OUT_REASON="kernel-devel not installed" ;;
      *) OUT_BUILT=false; OUT_KVER="$(kdevel_kver)"; OUT_REASON="build failed (make returned non-zero or no ena.ko)" ;;
    esac
  fi
}

# resolve_version : explicit ENA_VERSION wins; else the per-major pin (production
# default), resolved against the running OS before the build.
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

# Tests source this script for the pure pin/resolver logic without installing:
# ENA_LIB_ONLY=1 stops here, after the helpers + per-major pins are defined.
[ "${ENA_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

resolve_version

OUT_BUILT=false; OUT_KVER=""; OUT_REASON=""
run_build

if [ "${ENA_INSTALLTEST}" = "1" ]; then
  emit_result "${OUT_BUILT}" "${OUT_KVER}" "${OUT_REASON}"
  [ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
  exit 0
fi

# --- production mode: install the freshly built module ------------------------
if [ "${OUT_BUILT}" != "true" ]; then
  log "ENA build did not succeed: ${OUT_REASON}"
  [ -n "${BUILT_DEST}" ] && rm -rf "${BUILT_DEST}"
  exit 1
fi
log "installing ena.ko for kernel ${OUT_KVER}"
make -C "/usr/src/kernels/${OUT_KVER}" "M=${BUILT_SRC}" modules_install >/dev/null 2>&1 || true
depmod -a "${OUT_KVER}" || true
rm -rf "${BUILT_DEST}"
log "done (load + device attach is L4 - not attempted here)"
