#!/usr/bin/env bash
#==============================================================================
# install-aws_ssm-agent.sh - install the AWS SSM Agent on a RHEL-family host,
# and - in test mode - decide whether a given version installs and runs, and
# (per the init system) whether the unit is enable-able. Self-contained. Named to
# match tests/aws_ssm-agent/; run-ssm-installtest-matrix.sh kicks it with params.
#
# Two modes:
#   1. Production (SSM_INSTALLTEST=0): install the pinned/requested SSM RPM, then
#      enable amazon-ssm-agent for boot via whichever init system is present
#      (systemd -> chkconfig/SysV -> upstart).
#   2. Test (SSM_INSTALLTEST=1): install the RPM, run `amazon-ssm-agent -version`;
#      if SSM_INIT_MODE=systemd, enable the unit; emit one
#      [aws_ssm-agent][installtest][result] {json} line.
#
# Every failure path still emits {"status":"fail",...} (die). Axes glibc +
# init_mode. The matrix applies the verdict; this script emits raw facts.
#
# Env:  SSM_VERSION       (default: per-major pin below)
#       SSM_INSTALLTEST   (0|1; default 0)
#       SSM_INIT_MODE     (none|systemd; default none)
#       SSM_RPM_BASEURL   (default https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent)
#       INSECURE_TLS      (0|1; default 0)
#==============================================================================
set -uo pipefail

SSM_VERSION="${SSM_VERSION:-}"
SSM_INSTALLTEST="${SSM_INSTALLTEST:-0}"
SSM_INIT_MODE="${SSM_INIT_MODE:-none}"
RPM_BASEURL="${SSM_RPM_BASEURL:-https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent}"
INSECURE_TLS="${INSECURE_TLS:-0}"

# Per-RHEL-major pins (production default; matrix passes one in test mode). RHEL 6
# (EOL; fragile EL6 NSS/glibc combo) is pinned to a known-good full-feature build
# at the compliance floor (>= 3.3.3598.0 separates full-feature agents from
# ec2messages-only ones); RHEL 7-10 track the latest alias.
SSM_VERSION_RHEL6="${SSM_VERSION_RHEL6:-3.3.3598.0}"
SSM_VERSION_RHEL7="${SSM_VERSION_RHEL7:-latest}"
SSM_VERSION_RHEL8="${SSM_VERSION_RHEL8:-latest}"
SSM_VERSION_RHEL9="${SSM_VERSION_RHEL9:-latest}"
SSM_VERSION_RHEL10="${SSM_VERSION_RHEL10:-latest}"

OSMAJOR=""; GLIBC=""; INSTALLED="false"; RAN="false"; SVC="false"; RESULT_EMITTED=0

log() { printf '%s [install-aws_ssm-agent] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

die() {
  log "ERROR: $*"
  if [ "${SSM_INSTALLTEST}" = "1" ] && [ "${RESULT_EMITTED}" = "0" ]; then
    RESULT_EMITTED=1
    printf '[aws_ssm-agent][installtest][result] {"status":"fail","tool":"aws_ssm-agent","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"reason":"%s"}\n' \
      "${OSMAJOR}" "${SSM_VERSION}" "${SSM_INIT_MODE}" "${GLIBC}" "${INSTALLED}" "${RAN}" "${SVC}" "$(json_escape "$*")"
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
host_glibc() {
  rpm -q --qf '%{VERSION}\n' glibc 2>/dev/null | head -1 && return 0
  ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$'
}
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

pkgmgr() { for m in dnf yum; do command -v "${m}" >/dev/null 2>&1 && { printf '%s' "${m}"; return 0; }; done; printf 'none'; }

rpm_url() {
  if [ "${SSM_VERSION}" = "latest" ]; then printf '%s/latest/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}"
  else printf '%s/%s/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}" "${SSM_VERSION}"; fi
}

install_rpm() {
  local url tmp mgr
  local -a opts
  url="$(rpm_url)"; tmp="$(mktemp -d)"; mgr="$(pkgmgr)"
  pm_neutralize_rhsm_if_anonymous
  local -a copts=(-fsSL --retry 2 -o "${tmp}/ssm.rpm")
  [ "${INSECURE_TLS}" = "1" ] && copts+=(-k)
  log "fetching ${url}"
  curl "${copts[@]}" "${url}" || { rm -rf "${tmp}"; die "fetch failed: ${url}"; }
  opts=(-y install "${tmp}/ssm.rpm")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(--setopt=sslverify=0)
  if [ "${mgr}" != "none" ]; then
    run_pm "${mgr}" "${opts[@]}" >/dev/null 2>&1 || { rm -rf "${tmp}"; die "rpm install failed (dependency closure) via ${mgr}"; }
  else
    rpm -i "${tmp}/ssm.rpm" >/dev/null 2>&1 || { rm -rf "${tmp}"; die "rpm -i failed (no dnf/yum; unresolved deps?)"; }
  fi
  rm -rf "${tmp}"
}

# enable_for_boot : enable amazon-ssm-agent via the available init system.
# echoes true if enabled, false otherwise. systemd -> chkconfig/SysV -> upstart.
enable_for_boot() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl enable amazon-ssm-agent >/dev/null 2>&1; then printf 'true'; return 0; fi
    log "WARNING: systemctl enable amazon-ssm-agent failed; the RPM preset may still enable it"
  elif command -v chkconfig >/dev/null 2>&1 && [ -f /etc/init.d/amazon-ssm-agent ]; then
    if chkconfig amazon-ssm-agent on >/dev/null 2>&1; then
      log "enabled amazon-ssm-agent via chkconfig (SysV)"; printf 'true'; return 0
    fi
    log "WARNING: chkconfig amazon-ssm-agent on failed"
  elif [ -f /etc/init/amazon-ssm-agent.conf ]; then
    log "amazon-ssm-agent ships an upstart job; it starts on boot via its 'start on' stanza"
    printf 'true'; return 0
  else
    log "WARNING: no recognized init integration for amazon-ssm-agent"
  fi
  printf 'false'
}

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

trap 'die "unexpected error (line ${LINENO})"' ERR

OSMAJOR="$(os_major)"
GLIBC="$(host_glibc)"
resolve_version

if [ "${SSM_INSTALLTEST}" = "1" ]; then
  install_rpm
  INSTALLED="true"
  if amazon-ssm-agent -version >/dev/null 2>&1; then RAN="true"; else RAN="false"; fi
  if [ "${SSM_INIT_MODE}" = "systemd" ]; then SVC="$(enable_for_boot)"; fi
  RESULT_EMITTED=1
  printf '[aws_ssm-agent][installtest][result] {"status":"ok","tool":"aws_ssm-agent","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s}\n' \
    "${OSMAJOR}" "${SSM_VERSION}" "${SSM_INIT_MODE}" "${GLIBC}" "${INSTALLED}" "${RAN}" "${SVC}"
  exit 0
fi

# --- production mode ----------------------------------------------------------
log "installing SSM Agent (${SSM_VERSION}); init mode ${SSM_INIT_MODE}"
install_rpm
SVC="$(enable_for_boot)"
if [ "${SSM_INIT_MODE}" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl start amazon-ssm-agent || true
fi
amazon-ssm-agent -version || true
log "done (service_enabled=${SVC})"
