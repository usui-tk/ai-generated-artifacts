#!/usr/bin/env bash
#==============================================================================
# install-aws_ssm-agent.sh - install the AWS SSM Agent on a RHEL-family host,
# and - in test mode - decide whether a given version installs and runs, and
# (systemd) whether the unit is enable-able. Self-contained. Named to match
# tests/aws_ssm-agent/; run-ssm-installtest-matrix.sh kicks it with parameters.
#
# Two modes:
#   1. Production (SSM_INSTALLTEST=0): install the requested SSM RPM; if
#      SSM_INIT_MODE=systemd, enable + start amazon-ssm-agent.
#   2. Test (SSM_INSTALLTEST=1): install the RPM, run `amazon-ssm-agent -version`;
#      if SSM_INIT_MODE=systemd, `systemctl enable amazon-ssm-agent`; emit one
#      [aws_ssm-agent][installtest][result] {json} line for the matrix ledger.
#
# Axes glibc + init_mode (the design plan sec 11.2). The matrix applies the
# verdict; this script emits the raw observation (installed/ran/service_enabled).
#
# Env:  SSM_VERSION       (e.g. 3.3.4793.0; required in test mode)
#       SSM_INSTALLTEST   (0|1; default 0)
#       SSM_INIT_MODE     (none|systemd; default none)
#       SSM_RPM_BASEURL   (default https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent)
#       INSECURE_TLS      (0|1; default 0)
# Requires: curl, rpm, dnf|yum. Network: the S3 RPM over *.amazonaws.com.
#==============================================================================
set -euo pipefail

SSM_VERSION="${SSM_VERSION:-}"
SSM_INSTALLTEST="${SSM_INSTALLTEST:-0}"

# Per-RHEL-major pins: the SSM Agent version the test matrix validated for each
# major. RHEL 6 (EOL; the EL6 NSS/glibc combo is fragile) is pinned to a known-
# good full-feature build at the compliance floor (>= 3.3.3598.0 separates full-
# feature agents from ec2messages-only ones); RHEL 7-10 track the latest alias.
# An explicit SSM_VERSION overrides these (the matrix passes one in test mode).
SSM_VERSION_RHEL6="${SSM_VERSION_RHEL6:-3.3.3598.0}"
SSM_VERSION_RHEL7="${SSM_VERSION_RHEL7:-latest}"
SSM_VERSION_RHEL8="${SSM_VERSION_RHEL8:-latest}"
SSM_VERSION_RHEL9="${SSM_VERSION_RHEL9:-latest}"
SSM_VERSION_RHEL10="${SSM_VERSION_RHEL10:-latest}"
SSM_INIT_MODE="${SSM_INIT_MODE:-none}"
RPM_BASEURL="${SSM_RPM_BASEURL:-https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent}"
INSECURE_TLS="${INSECURE_TLS:-0}"

log() { printf '%s [install-aws_ssm-agent] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

os_major() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ( . /etc/os-release; printf '%s' "${VERSION_ID%%.*}" )
  elif [ -r /etc/redhat-release ]; then
    sed -n 's/.*release \([0-9]\+\).*/\1/p' /etc/redhat-release | head -1
  fi
}

host_glibc() {
  rpm -q --qf '%{VERSION}\n' glibc 2>/dev/null | head -1 && return 0
  ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$'
}

pkgmgr() { for m in dnf yum; do command -v "${m}" >/dev/null 2>&1 && { printf '%s' "${m}"; return 0; }; done; printf 'none'; }

rpm_url() {
  if [ "${SSM_VERSION}" = "latest" ]; then
    printf '%s/latest/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}"
  else
    printf '%s/%s/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}" "${SSM_VERSION}"
  fi
}

install_rpm() { # rc 0 on install (dep closure resolved)
  local url tmp mgr
  local -a opts
  url="$(rpm_url)"; tmp="$(mktemp -d)"; mgr="$(pkgmgr)"
  local -a copts=(-fsSL --retry 2 -o "${tmp}/ssm.rpm")
  [ "${INSECURE_TLS}" = "1" ] && copts+=(-k)
  log "fetching ${url}"
  curl "${copts[@]}" "${url}" || { rm -rf "${tmp}"; return 1; }
  opts=(-y install "${tmp}/ssm.rpm")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(--setopt=sslverify=0)
  if [ "${mgr}" != "none" ]; then
    "${mgr}" "${opts[@]}" >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
  else
    rpm -i "${tmp}/ssm.rpm" >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
  fi
  rm -rf "${tmp}"
}

emit_result() { # <installed> <ran> <service_enabled> <reason>
  printf '[aws_ssm-agent][installtest][result] {"tool":"aws_ssm-agent","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"reason":"%s"}\n' \
    "$(os_major)" "${SSM_VERSION}" "${SSM_INIT_MODE}" "$(host_glibc)" "$1" "$2" "$3" "$4"
}

# resolve_version : explicit SSM_VERSION wins; else the per-major pin (production
# default), resolved against the running OS before install.
resolve_version() {
  [ -n "${SSM_VERSION}" ] && return 0
  case "$(os_major)" in
    6)  SSM_VERSION="${SSM_VERSION_RHEL6}" ;;
    7)  SSM_VERSION="${SSM_VERSION_RHEL7}" ;;
    8)  SSM_VERSION="${SSM_VERSION_RHEL8}" ;;
    9)  SSM_VERSION="${SSM_VERSION_RHEL9}" ;;
    10) SSM_VERSION="${SSM_VERSION_RHEL10}" ;;
    *)  SSM_VERSION="latest" ;;
  esac
}

# Tests source this script for the pure pin/resolver logic without installing:
# SSM_LIB_ONLY=1 stops here, after the helpers + per-major pins are defined.
[ "${SSM_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

resolve_version

if [ "${SSM_INSTALLTEST}" = "1" ]; then
  if ! install_rpm; then
    emit_result false false false "rpm install failed (dependency closure or fetch error)"
    exit 0
  fi
  if amazon-ssm-agent -version >/dev/null 2>&1; then ran=true; else ran=false; fi
  svc=false
  if [ "${SSM_INIT_MODE}" = "systemd" ]; then
    if systemctl enable amazon-ssm-agent >/dev/null 2>&1; then svc=true; fi
  fi
  emit_result true "${ran}" "${svc}" ""
  exit 0
fi

# --- production mode ----------------------------------------------------------
log "installing SSM Agent (${SSM_VERSION}); init mode ${SSM_INIT_MODE}"
install_rpm || { log "ERROR: SSM Agent install failed"; exit 1; }
if [ "${SSM_INIT_MODE}" = "systemd" ]; then
  systemctl enable amazon-ssm-agent || true
  systemctl start amazon-ssm-agent || true
fi
amazon-ssm-agent -version || true
log "done"
