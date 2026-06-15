#!/usr/bin/env bash
#
# install-ssm-agent.sh
#
# Install the AWS Systems Manager (SSM) Agent on an Oracle Linux image/instance,
# and -- in test mode -- determine whether a given agent version INSTALLS and
# actually RUNS on this (kernel, glibc). SELF-CONTAINED (no shared library).
#
# Two execution environments, mirroring install-ena-driver.sh:
#   1. Production (SSM_INSTALLTEST=0, default): install the pinned/requested SSM
#      Agent RPM on a real OL instance. NOTE: this is NOT wired into
#      build-ol-aws-ami.sh today -- whether SSM joins the AMI pipeline is the
#      maintainer's call AFTER the install+run test report (a new B.10).
#   2. Test (SSM_INSTALLTEST=1): the container install-test environment used by
#      tests/ssm/run-ssm-installtest-matrix.sh. Installs the requested version
#      into a disposable clean-core rootfs, records the (kernel, glibc) context,
#      runs the agent binary locally (no AWS / no IMDS), and emits a single-line
#      [result] JSON the matrix ledger consumes.
#
# WHY (kernel, glibc): the SSM Agent is a Go program. Newer RPMs are effectively
# static (no glibc Requires) -> runnability is gated by the KERNEL (the Go
# runtime's minimum supported Linux rises per toolchain): too old -> "installs
# but won't run". Older versions are dynamically linked (Requires glibc) -> the
# OS glibc gates install/run. So the real surface is (kernel, glibc) x version.
# The OL target kernel is read from the rpm db (`rpm -q kernel-uek`, the UEK
# provisioned in the test the same way the ENA path provisions it), and `rpm -q
# glibc` is the OL rootfs's glibc -- both authoritative from rpm. `uname -r` is
# the live host/runner kernel the binary actually executes against (in a
# container NOT the OL UEK); it is recorded separately as test_host_kernel.
#
# The agent VERSION is the practical proxy for the AWS endpoint requirement:
# from 2026-06-16 SSM Run Command stops supporting instances on the legacy
# ec2messages endpoint; agents >= 3.3.3598.0 use ssmmessages. ec2messages vs
# ssmmessages is RUNTIME (a real instance + AWS) -> not container-testable; the
# installed+running version vs 3.3.3598.0 is the in-container proxy (analogous to
# the ENA compile-test proxying boot/ethtool B-T7/B-T8).
#
# Source: aws/amazon-ssm-agent. RPM URL (linux_amd64):
#   https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/<VERSION>/linux_amd64/amazon-ssm-agent.rpm
#   (plus the /latest/ alias). This script is original.
#
set -euo pipefail

# ---- pinned version (overridable) ------------------------------------------
# Production default: "latest" (the /latest/ S3 alias). A specific version is
# selected with SSM_AGENT_VERSION (the test matrix always sets it).
SSM_AGENT_VERSION="${SSM_AGENT_VERSION:-latest}"
SSM_RPM_BASEURL="${SSM_RPM_BASEURL:-https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent}"
SSM_RPM_ARCH="${SSM_RPM_ARCH:-linux_amd64}"

# ---- execution-environment switch (default = production) -------------------
# SSM_INSTALLTEST=1 selects the container install-test environment (install +
# local run only -- no AWS, no IMDS). Default 0 = production.
SSM_INSTALLTEST="${SSM_INSTALLTEST:-0}"
# INSECURE_TLS=1 drops TLS peer verification for the test-mode network commands
# only (MITM dev proxy / EL6 NSS trust gaps). Consulted only in the test branch.
INSECURE_TLS="${INSECURE_TLS:-0}"

# Execution-environment tag, injected by every emitter so output is tagged by
# environment WITHOUT changing call sites (mirrors install-ena-driver.sh).
_env_tag() { if [[ "${SSM_INSTALLTEST}" == "1" ]]; then printf '[installtest]'; fi; }
log()   { echo "[ssm-agent]$(_env_tag) $*"; }
stage() { echo "[ssm-agent]$(_env_tag)[stage] $*"; }

# Per-entry context, filled in as it is measured, so the die-handler can emit a
# fully-populated fail result.
osmajor=""; ssm_version="${SSM_AGENT_VERSION}"; kver=""; glibc=""; test_host_kernel=""
installed_version=""; ran="false"; run_method=""

die() {
  echo "[ssm-agent]$(_env_tag)[ERROR] $*" >&2
  if [[ "${SSM_INSTALLTEST}" == "1" ]]; then
    printf '[ssm-agent][installtest][result] {"status":"fail","osmajor":"%s","ssm_version":"%s","kver":"%s","test_host_kernel":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s","reason":"%s"}\n' \
      "${osmajor}" "${ssm_version}" "${kver}" "${test_host_kernel}" "${glibc}" "${installed_version}" "${ran}" "${run_method}" \
      "$(printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
  exit 1
}

# ---- detect OS major -------------------------------------------------------
detect_osmajor() {
  local v=""
  if [[ -r /etc/oracle-release ]]; then
    v="$(grep -oE '[0-9]+' /etc/oracle-release | head -1 || true)"
  fi
  if [[ -z "${v}" && -r /etc/os-release ]]; then
    v="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID%%.*}")"
  fi
  printf '%s' "${v}"
}

# ---- the RPM URL for a version (or the /latest/ alias) ---------------------
rpm_url_for() {
  local ver="$1"
  printf '%s/%s/%s/amazon-ssm-agent.rpm' "${SSM_RPM_BASEURL}" "${ver}" "${SSM_RPM_ARCH}"
}

# ---- fetch the RPM to a local file (sidesteps the EL6 yum-over-HTTPS NSS quirk:
# curl the artifact, then install the LOCAL file). Honors INSECURE_TLS. ---------
fetch_rpm() {
  local url="$1" dest="$2"
  local -a opts=(-fsSL -o "${dest}" --max-time "${SSM_FETCH_TIMEOUT:-120}")
  if [[ "${INSECURE_TLS}" == "1" ]]; then opts+=(-k); fi
  curl "${opts[@]}" "${url}"
}

# ---- read the installed agent version (empty if not installed) -------------
installed_agent_version() {
  rpm -q --qf '%{VERSION}' amazon-ssm-agent 2>/dev/null | grep -E '^[0-9]' | head -1 || true
}

# ---- run the agent binary LOCALLY (no AWS/IMDS) to prove the Go runtime +
# linked libs load on this (kernel, glibc). On success echoes the METHOD used
# and returns 0; on failure returns non-zero and echoes nothing. (Echoing the
# method -- rather than setting a variable -- is deliberate: the caller runs this
# in a command substitution, a subshell, so a variable set here would not survive.)
# A version print exercises the Go runtime + linked libs, the meaningful binary-
# load check; ssm-cli get-instance-information needs IMDS (169.254.169.254),
# absent in a container, so it is only an opportunistic fallback probe.
agent_runs_locally() {
  local out=""
  if [[ -x /usr/bin/amazon-ssm-agent ]]; then
    if out="$(/usr/bin/amazon-ssm-agent -version 2>&1)" && printf '%s' "${out}" | grep -qiE '[0-9]+\.[0-9]+\.[0-9]+'; then
      printf 'amazon-ssm-agent -version'; return 0
    fi
  fi
  if [[ -x /usr/bin/ssm-cli ]]; then
    if out="$(/usr/bin/ssm-cli get-instance-information 2>&1)" && [[ -n "${out}" ]] && ! printf '%s' "${out}" | grep -qiE 'panic|segmentation|cannot execute'; then
      printf 'ssm-cli get-instance-information'; return 0
    fi
  fi
  return 1
}

osmajor="$(detect_osmajor)"
[[ -n "${osmajor}" ]] || die "cannot determine Oracle Linux major version"

# The runner/host kernel the agent binary actually executes against. In a
# container this is the host (runner) kernel, NOT the OL UEK -- recorded as-is
# for honesty (the install+run was validated against this kernel).
test_host_kernel="$(uname -r 2>/dev/null || true)"

# ---- SSM_INSTALLTEST: provision the OL UEK kernel into the container --------
# Mirrors install-ena-driver.sh's ENA_BUILDTEST kernel provisioning, but installs
# the kernel-uek PACKAGE ONLY (no -devel/gcc/make/dkms): the SSM agent does not
# build a module, so kernel-uek is provisioned solely so the OL target kernel can
# be read authoritatively from the rpm db (rpm -q kernel-uek), exactly the way
# glibc is -- the same (kernel-less clean-core, install-at-test-time) architecture
# as ENA. A container shares the host kernel, so this does NOT change what the
# binary runs on (test_host_kernel above); it records the kernel a real OL
# instance would run. kernel-uek comes from the UEK repo; its deps resolve from
# the default-enabled base OS repo, so no EPEL is needed. sslverify is dropped
# only at INSECURE_TLS=1. Production (no SSM_INSTALLTEST) never enters this block.
if [[ "${SSM_INSTALLTEST}" == "1" ]]; then
  case "${osmajor}" in
    6) bt_uek_repo="ol6_UEKR4" ;;
    7) bt_uek_repo="ol7_UEKR6" ;;
    8)
      # OL8 slim ships dnf only; bootstrap the yum compat for the install below.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL8"
      else
        dnf -y install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL8"
      fi
      bt_uek_repo="ol8_UEKR6" ;;
    9)
      # OL9 slim ships dnf only; bootstrap the yum compat for the install below.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL9"
      else
        dnf -y install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL9"
      fi
      bt_uek_repo="ol9_UEKR7" ;;
    10)
      # OL10 slim ships dnf only; bootstrap the yum compat for the install below.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL10"
      else
        dnf -y install yum >/dev/null 2>&1 || die "SSM_INSTALLTEST: failed to bootstrap yum on OL10"
      fi
      bt_uek_repo="ol10_UEKR8" ;;
    *) die "SSM_INSTALLTEST: OS major ${osmajor} not wired for the container kernel record" ;;
  esac
  stage "provisioning kernel-uek (OL target-kernel version record) via ${bt_uek_repo}"
  if [[ "${INSECURE_TLS}" == "1" ]]; then
    yum -y --setopt=sslverify=false --enablerepo="${bt_uek_repo}" install kernel-uek \
      || die "SSM_INSTALLTEST: failed to provision kernel-uek"
  else
    yum -y --enablerepo="${bt_uek_repo}" install kernel-uek \
      || die "SSM_INSTALLTEST: failed to provision kernel-uek"
  fi
fi

# Target OL kernel, read authoritatively from the rpm db (like glibc below). In
# SSM_INSTALLTEST the kernel-uek just provisioned is the OL UEK a real instance
# would run; on a real OL instance (production/standalone) the live UEK is already
# installed. Falls back to the host kernel only if no kernel-uek is present.
kver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-uek 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -1 || true)"
[[ -n "${kver}" ]] || kver="${test_host_kernel}"
glibc="$(rpm -q --qf '%{VERSION}' glibc 2>/dev/null | grep -E '^[0-9]' | head -1 || true)"
[[ -n "${glibc}" ]] || glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"

log "OL${osmajor} | kver ${kver:-?} (host ${test_host_kernel:-?}) | glibc ${glibc:-?} | requested SSM ${ssm_version}"

# ---- install ---------------------------------------------------------------
rpm_url="$(rpm_url_for "${ssm_version}")"
rpmfile="$(mktemp --suffix=.rpm)"
trap 'rm -f "${rpmfile}"' EXIT

stage "fetch ${rpm_url}"
fetch_rpm "${rpm_url}" "${rpmfile}" || die "RPM fetch failed for ${ssm_version} (${rpm_url})"

stage "install amazon-ssm-agent ${ssm_version}"
# Install the LOCAL RPM with rpm -Uvh directly -- NOT `yum localinstall`. The SSM
# Agent RPM's only real dependency is glibc, which the base OS already provides,
# so no repository metadata is needed; going through yum would pull in the OL
# repos and, on EL6, hit the yum-over-HTTPS NSS trust quirk (repomd.xml "peer
# cert cannot be verified"). rpm -Uvh resolves deps against the local rpm DB:
#   * a DYNAMIC version whose glibc requirement exceeds the OS glibc fails here
#     with a real dependency error -- the faithful "won't install" signal;
#   * a STATIC version (no glibc Requires) installs regardless.
# The RPM is unsigned-to-us (NOKEY warning) and its %post tries to start the
# service via the init system, which is absent in a container ("Unable to connect
# to Upstart"); both are benign -- rpm still returns 0 and places the binary,
# which is what the install+run test needs (service management is a real-instance
# concern, not an install/run-capability one).
rpm -Uvh --replacepkgs "${rpmfile}" 2>&1 \
  || die "install-fail: rpm install of amazon-ssm-agent ${ssm_version} failed (dependency/glibc unmet or payload error)"

installed_version="$(installed_agent_version)"
[[ -n "${installed_version}" ]] || die "install-fail: amazon-ssm-agent not present after install"
# Version-provenance guard (mirrors ENA's ko_version check): the RPM may carry a
# version string that differs from the requested tag for the /latest/ alias; for
# a specific request, a mismatch means the wrong artifact installed.
if [[ "${ssm_version}" != "latest" && "${installed_version}" != "${ssm_version}" ]]; then
  die "version-mismatch: requested ${ssm_version} but installed ${installed_version}"
fi
log "installed amazon-ssm-agent ${installed_version}"

# ---- run locally -----------------------------------------------------------
stage "run agent binary locally (no AWS/IMDS)"
if run_method="$(agent_runs_locally)"; then
  ran="true"
  log "agent runs locally via '${run_method}'"
else
  ran="false"
  die "installs-but-wont-run: amazon-ssm-agent ${installed_version} installed but the binary did not run on this (kernel ${kver}, glibc ${glibc}) -- Go runtime/kernel or a runtime-lib miss"
fi

# ---- SSM_INSTALLTEST: structured success result for the matrix -------------
if [[ "${SSM_INSTALLTEST}" == "1" ]]; then
  printf '[ssm-agent][installtest][result] {"status":"ok","osmajor":"%s","ssm_version":"%s","kver":"%s","test_host_kernel":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s"}\n' \
    "${osmajor}" "${ssm_version}" "${kver}" "${test_host_kernel}" "${glibc}" "${installed_version}" "${ran}" "${run_method}"
fi

log "done."
