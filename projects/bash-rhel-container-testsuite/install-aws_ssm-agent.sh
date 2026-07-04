#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Install the AWS SSM Agent from the AWS S3 RPM on a RHEL-family host or
#   container; in test mode, record install/run/enable facts per init mode
#   (none|systemd) and emit a single-line [result] JSON for the matrix ledger.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl, rpm + yum/dnf; root for production; network to
#   *.amazonaws.com (INSECURE_TLS=1 for a MITM dev proxy).
# ----- Usage examples -------------------------------------------------------
#   sudo bash install-aws_ssm-agent.sh                       # production install
#   SSM_INSTALLTEST=1 SSM_INIT_MODE=systemd bash install-aws_ssm-agent.sh
# ----- Known limitations ----------------------------------------------------
#   Service activation is only observable under systemd PID1 (ubi-init booted);
#   RHEL 6 anonymous mode depends on base-image dependency closure (Tier C).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
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
set -euo pipefail

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

OSMAJOR=""; GLIBC=""; INSTALLED="false"; RAN="false"; SVC="false"; RESULT_EMITTED=0; PTWARN=0

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

# die_unsupported : like die, but the outcome is a MEASURED platform
# incompatibility, not a failure of this run - status "unsupported" (r48).
die_unsupported() {
  log "UNSUPPORTED: $*"
  if [ "${SSM_INSTALLTEST}" = "1" ] && [ "${RESULT_EMITTED}" = "0" ]; then
    RESULT_EMITTED=1
    printf '[aws_ssm-agent][installtest][result] {"status":"unsupported","tool":"aws_ssm-agent","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"reason":"%s"}\n' \
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

pkgmgr() { for m in dnf yum; do command -v "${m}" >/dev/null 2>&1 && { printf '%s' "${m}"; return 0; }; done; printf 'none'; }

# pm_install_local_rpm <mgr> <rpm> : install a LOCAL rpm whose dependency closure
# is self-contained. The SSM Agent is a static Go binary; its only Requires are
# /bin/sh + rtld(GNU_HASH), always present in any RHEL/UBI base (verified with
# `rpm -qpR amazon-ssm-agent.rpm`). dnf/yum would otherwise refresh EVERY enabled
# repo's metadata before even a local install, so a single unreachable or
# major-mismatched repo (a host redhat.repo bind-mounted into a different-major
# UBI container, an unentitled anonymous base, or a transient CDN error) fails
# the transaction for reasons unrelated to this rpm - historically mislabelled
# "dependency closure". So install OFFLINE first (--disablerepo='*', which needs
# no repo metadata for a dep-free rpm) and only fall back to a repo-enabled
# resolve if that genuinely fails (a future rpm growing a real dependency). The
# package manager's real stderr is captured into PM_INSTALL_ERR, never masked.
PM_INSTALL_ERR=""
pm_install_local_rpm() {
  local mgr="$1" rpm_path="$2" errf
  local -a cmd=("${mgr}" -y)   # never empty -> "${cmd[@]}" is set -u safe on bash 4.1+ (RHEL6/7)
  [ "${INSECURE_TLS}" = "1" ] && cmd+=(--setopt=sslverify=0)
  errf="$(mktemp)"
  # Tier 1: offline - a dependency-free rpm needs no repo metadata at all.
  if run_pm "${cmd[@]}" --disablerepo='*' install "${rpm_path}" >/dev/null 2>"${errf}"; then
    rm -f "${errf}"; PM_INSTALL_ERR=""; return 0
  fi
  # Tier 2: repo-enabled resolve - only reached if Tier 1 failed (e.g. an unmet
  # real dependency in some future agent build); append its stderr too.
  if run_pm "${cmd[@]}" install "${rpm_path}" >/dev/null 2>>"${errf}"; then
    rm -f "${errf}"; PM_INSTALL_ERR=""; return 0
  fi
  # Surface the actual package-manager error (last ~200 chars), never a guess.
  PM_INSTALL_ERR="$(tr '\n' ' ' < "${errf}" | sed 's/  */ /g; s/^ *//; s/ *$//' | tail -c 200)"
  rm -f "${errf}"
  return 1
}

rpm_url() {
  if [ "${SSM_VERSION}" = "latest" ]; then printf '%s/latest/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}"
  else printf '%s/%s/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}" "${SSM_VERSION}"; fi
}

install_rpm() {
  local url tmp mgr
  url="$(rpm_url)"; tmp="$(mktemp -d)"; mgr="$(pkgmgr)"
  pm_neutralize_rhsm_if_anonymous
  local -a copts=(-fsSL --retry 2 -o "${tmp}/ssm.rpm")
  [ "${INSECURE_TLS}" = "1" ] && copts+=(-k)
  log "fetching ${url}"
  curl "${copts[@]}" "${url}" || { rm -rf "${tmp}"; die "fetch failed: ${url}"; }
  if [ "${mgr}" != "none" ]; then
    pm_install_local_rpm "${mgr}" "${tmp}/ssm.rpm" \
      || { local reason="${PM_INSTALL_ERR}" have=""
           # r50 (measured 2026-07-04, el6 chroot): a %posttrans scriptlet
           # error does NOT mean the agent is unusable - the rpm's files land
           # and the binary runs (user-verified track record: 3.0.1479.0 on
           # real RHEL 6). The scriptlet only registers the service, which
           # cannot work without a RUNNING init (absent in containers/chroots).
           # So MEASURE instead of assuming: if the requested version is now
           # installed, continue with a warning and let the run check decide;
           # classify unsupported only when the package did not land (r48's
           # el6 signature) - never on a mere service-registration failure.
           # NB: yum prints "does not update installed package" on STDOUT
           # (discarded); stderr carries only "Error: Nothing to do" - match
           # that too. The rpm -q version check below is the real guard.
           case "${reason}" in
             *"POSTTRANS scriptlet"*|*"does not update installed package"*|*"Nothing to do"*)
               have="$(rpm -q --qf '%{VERSION}' amazon-ssm-agent 2>/dev/null || true)" ;;
           esac
           if [ -n "${have}" ] && { [ "${SSM_VERSION}" = "latest" ] || [ "${have}" = "${SSM_VERSION}" ]; }; then
             PTWARN=1
             log "WARNING: %posttrans scriptlet failed (no running init in this container/chroot); package ${have} installed - continuing to the run check"
           else
             rm -rf "${tmp}"
             case "${OSMAJOR}:${reason}" in
               6:*"POSTTRANS scriptlet"*|6:*"does not update installed package"*|6:*"Nothing to do"*)
                 die_unsupported "agent %posttrans requires systemd; EL6/upstart cannot run this agent${reason:+: ${reason}}" ;;
             esac
             die "rpm install via ${mgr} failed${reason:+: ${reason}}"
           fi; }
  else
    local rpmerr
    if ! rpmerr="$(rpm -i "${tmp}/ssm.rpm" 2>&1 1>/dev/null)"; then
      rpmerr="$(printf '%s' "${rpmerr}" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//' | tail -c 200)"
      rm -rf "${tmp}"
      die "rpm -i failed (no dnf/yum)${rpmerr:+: ${rpmerr}}"
    fi
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
  # r50: after a tolerated %posttrans warning, the run check is the judge -
  # a binary that does not even run on EL6 IS a platform incompatibility.
  if [ "${RAN}" != "true" ] && [ "${PTWARN}" = "1" ] && [ "${OSMAJOR}" = "6" ]; then
    die_unsupported "agent ${SSM_VERSION} installed but its binary does not run on EL6 (glibc ${GLIBC})"
  fi
  if [ "${SSM_INIT_MODE}" = "systemd" ]; then SVC="$(enable_for_boot)"; fi
  RESULT_EMITTED=1
  _note=""; [ "${PTWARN}" = "1" ] && _note="%posttrans scriptlet warning tolerated (no running init in this container/chroot; service registration not performed)"
  printf '[aws_ssm-agent][installtest][result] {"status":"ok","tool":"aws_ssm-agent","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"reason":"%s"}\n' \
    "${OSMAJOR}" "${SSM_VERSION}" "${SSM_INIT_MODE}" "${GLIBC}" "${INSTALLED}" "${RAN}" "${SVC}" "$(json_escape "${_note}")"
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
